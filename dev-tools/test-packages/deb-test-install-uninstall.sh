#!/bin/bash
# Runs inside the systemd container started by run_in_systemd_container.sh.
# Tests that the package installs, the service starts, and the package uninstalls cleanly.
#
# Usage: deb-test-install-uninstall.sh <package-name>

set -euo pipefail

PACKAGE_NAME="$1"

dpkg -i "/test-packages/deb/${PACKAGE_NAME}"
if dpkg-query -W -f='${Status}' wazuh-dashboard 2>/dev/null | grep -q "install ok installed"; then
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

# Supply test credentials, as the indexer and the manager would.
install -d -m 0700 /etc/wazuh
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

apt-get remove --purge wazuh-dashboard -y
if dpkg-query -W -f='${Status}' wazuh-dashboard 2>/dev/null | grep -q "install ok installed"; then
  echo "Package not uninstalled"
  exit 1
else
  echo "Package uninstalled"
fi
