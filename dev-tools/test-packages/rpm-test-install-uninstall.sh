#!/bin/bash
# Runs as root on the allocated RPM test machine, next to the package copied there.
# Tests that the package installs, the service starts, and the package uninstalls cleanly.
#
# Usage: rpm-test-install-uninstall.sh <package-path>

set -euo pipefail

PACKAGE_NAME="$1"

rpm -i "${PACKAGE_NAME}"
if rpm -q wazuh-dashboard &>/dev/null; then
  echo "Package installed"
else
  echo "Package not installed"
  exit 1
fi

# A fresh install issues the TLS certificates from the shared CA, minting it on an empty host.
certs_dir=/etc/wazuh-dashboard/certs
for cert_file in dashboard.pem dashboard-key.pem root-ca.pem; do
  if [ "$(stat -c '%U:%G:%a' "${certs_dir}/${cert_file}" 2>/dev/null)" != "wazuh-dashboard:wazuh-dashboard:400" ]; then
    echo "Certificate ${cert_file} missing or with wrong ownership/mode"
    ls -la "${certs_dir}" || true
    exit 1
  fi
done
if openssl verify -purpose sslserver -CAfile /etc/wazuh/ca/root-ca.pem "${certs_dir}/dashboard.pem" >/dev/null &&
  cmp -s /etc/wazuh/ca/root-ca.pem "${certs_dir}/root-ca.pem"; then
  echo "Certificates issued from the shared CA"
else
  echo "Certificates do not chain to the shared CA"
  exit 1
fi

systemctl daemon-reload
systemctl enable wazuh-dashboard

# Without the peer credentials, --prestart must refuse to start the service.
if systemctl start wazuh-dashboard; then
  echo "Service started without credentials"
  exit 1
fi
prestart_output=$(/usr/share/wazuh-dashboard/bin/resolve-credentials --prestart 2>&1 || true)
if grep -q "MISSING WAZUH_INDEXER_KIBANASERVER_PASSWORD" <<<"${prestart_output}" &&
  grep -q "MISSING WAZUH_MANAGER_WUI_PASSWORD" <<<"${prestart_output}"; then
  echo "Service refused to start without credentials"
else
  echo "Service failed to start for an unexpected reason"
  journalctl -u wazuh-dashboard --no-pager | tail -50
  exit 1
fi
# Restart=always keeps retrying the failed start: stop it and clear the start rate limit.
systemctl stop wazuh-dashboard || true
systemctl reset-failed wazuh-dashboard || true

install -d -m 0700 /etc/wazuh

# A value the keystore would not store as text (a JSON number) must be reported as INVALID.
printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\nWAZUH_MANAGER_WUI_PASSWORD=%s\n' \
  '123456789e10' 'TestWui1Password' > /etc/wazuh/credentials.env
chmod 0600 /etc/wazuh/credentials.env
prestart_output=$(/usr/share/wazuh-dashboard/bin/resolve-credentials --prestart 2>&1 || true)
if grep -q "INVALID WAZUH_INDEXER_KIBANASERVER_PASSWORD" <<<"${prestart_output}"; then
  echo "JSON number rejected as a password"
else
  echo "JSON number not rejected as a password"
  echo "${prestart_output}"
  exit 1
fi

# Supply test credentials, as the indexer and the manager would.
printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\nWAZUH_MANAGER_WUI_PASSWORD=%s\n' \
  'TestKibana1Password' 'TestWui1Password' > /etc/wazuh/credentials.env
chmod 0600 /etc/wazuh/credentials.env

if ! systemctl start wazuh-dashboard; then
  journalctl -u wazuh-dashboard --no-pager | tail -50
  exit 1
fi
if systemctl status wazuh-dashboard | grep -q "active (running)"; then
  echo "Service running"
else
  echo "Service not running"
  journalctl -u wazuh-dashboard --no-pager | tail -50
  exit 1
fi

if runuser wazuh-dashboard --shell="/bin/bash" \
  --command="/usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore list" \
  | grep -q "^wazuh_ai_assistant.encryptionKey$"; then
  echo "AI assistant encryption key present in keystore"
else
  echo "AI assistant encryption key missing from keystore"
  exit 1
fi

yum remove -y wazuh-dashboard
rm -rf /var/lib/wazuh-dashboard/ /usr/share/wazuh-dashboard/ /etc/wazuh-dashboard/ /etc/wazuh/
if rpm -q wazuh-dashboard &>/dev/null; then
  echo "Package not uninstalled"
  exit 1
else
  echo "Package uninstalled"
fi
