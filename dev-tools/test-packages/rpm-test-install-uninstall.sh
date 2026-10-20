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

if [ -e /etc/wazuh ]; then
  echo "The install created /etc/wazuh"
  exit 1
fi

# A fresh install mints the dashboard's own CA, issues the TLS pair from it and publishes the CA.
config_dir=/etc/wazuh-dashboard
certs_dir="${config_dir}/certs"
ca_dir="${config_dir}/ca"
for cert_file in dashboard.pem dashboard-key.pem; do
  if [ "$(stat -c '%U:%G:%a' "${certs_dir}/${cert_file}" 2>/dev/null)" != "root:wazuh-dashboard:640" ]; then
    echo "Certificate ${cert_file} missing or with wrong ownership/mode"
    ls -la "${certs_dir}" || true
    exit 1
  fi
done
if [ "$(stat -c '%U:%G:%a' "${ca_dir}/root-ca.key" 2>/dev/null)" != "root:root:400" ]; then
  echo "CA key missing or with wrong ownership/mode"
  ls -la "${ca_dir}" || true
  exit 1
fi
if openssl verify -purpose sslserver -CAfile "${ca_dir}/root-ca.pem" "${certs_dir}/dashboard.pem" >/dev/null &&
  cmp -s "${ca_dir}/root-ca.pem" "${config_dir}/export/ca.pem"; then
  echo "Certificates issued from the dashboard CA, which is published in export/"
else
  echo "Certificates do not chain to the dashboard CA, or export/ca.pem is not that CA"
  exit 1
fi

systemctl daemon-reload
systemctl enable wazuh-dashboard

# Without the peers' exports, --prestart must refuse to start the service.
if systemctl start wazuh-dashboard; then
  echo "Service started without credentials"
  exit 1
fi
prestart_output=$(/usr/share/wazuh-dashboard/bin/resolve-credentials --prestart 2>&1 || true)
if grep -q "MISSING WAZUH_INDEXER_KIBANASERVER_PASSWORD" <<<"${prestart_output}" &&
  grep -q "MISSING WAZUH_MANAGER_WUI_PASSWORD" <<<"${prestart_output}" &&
  grep -q "MISSING ${certs_dir}/indexer-ca.pem" <<<"${prestart_output}"; then
  echo "Service refused to start without credentials and the indexer CA"
else
  echo "Service failed to start for an unexpected reason"
  echo "${prestart_output}"
  journalctl -u wazuh-dashboard --no-pager | tail -50
  exit 1
fi
# Restart=always keeps retrying the failed start: stop it and clear the start rate limit.
systemctl stop wazuh-dashboard || true
systemctl reset-failed wazuh-dashboard || true

# Publish what the indexer and the manager would in their export/ directories. Any CA
# certificate will do for the indexer's: the dashboard's own one is at hand.
indexer_export=/etc/wazuh-indexer/export
manager_export=/etc/wazuh-manager/export
install -d -m 0700 "${indexer_export}" "${manager_export}"
install -m 0644 "${ca_dir}/root-ca.pem" "${indexer_export}/ca.pem"

# A value the keystore would not store as text (a JSON number) must be reported as INVALID.
printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\n' '123456789e10' >"${indexer_export}/credentials.env"
printf 'WAZUH_MANAGER_WUI_PASSWORD=%s\n' 'TestWui1Password' >"${manager_export}/credentials.env"
chmod 0600 "${indexer_export}/credentials.env" "${manager_export}/credentials.env"
prestart_output=$(/usr/share/wazuh-dashboard/bin/resolve-credentials --prestart 2>&1 || true)
if grep -q "INVALID WAZUH_INDEXER_KIBANASERVER_PASSWORD" <<<"${prestart_output}"; then
  echo "JSON number rejected as a password"
else
  echo "JSON number not rejected as a password"
  echo "${prestart_output}"
  exit 1
fi

printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\n' 'TestKibana1Password' >"${indexer_export}/credentials.env"

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
bash "$(dirname "$0")/check-service-bind.sh"

if cmp -s "${indexer_export}/ca.pem" "${certs_dir}/indexer-ca.pem" &&
  [ -f "${certs_dir}/.indexer-ca.imported" ]; then
  echo "Indexer CA imported from its export/"
else
  echo "Indexer CA not imported from its export/"
  ls -la "${certs_dir}" || true
  exit 1
fi

echo "==> Checking the keystore for wazuh_ai_assistant.encryptionKey"
# Capture before grepping: `grep -q` closes the pipe on the first match, and under pipefail the
# keystore CLI's resulting EPIPE would fail the check.
if keystore_keys="$(runuser wazuh-dashboard --shell="/bin/bash" \
  --command="/usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore list")" &&
  grep -qx "wazuh_ai_assistant.encryptionKey" <<<"${keystore_keys}"; then
  echo "AI assistant encryption key present in keystore"
else
  echo "AI assistant encryption key missing from keystore"
  echo "Keystore entries: ${keystore_keys:-<none>}"
  exit 1
fi

echo "==> Checking the keystore mode and ownership"
keystore_file="${config_dir}/opensearch_dashboards.keystore"
keystore_stat="$(stat -c '%a %U:%G' "${keystore_file}")" || keystore_stat=""
if [ "${keystore_stat}" = "640 root:wazuh-dashboard" ]; then
  echo "Keystore is owned by root and readable by the service group"
else
  echo "Keystore mode or ownership is wrong: ${keystore_stat:-<missing>}"
  exit 1
fi

# A file left owned by the service user, which the removal must hand to root before userdel frees
# the ID.
operator_file="${config_dir}/operator-added.pem"
install -m 0600 -o wazuh-dashboard -g wazuh-dashboard /dev/null "${operator_file}"

yum remove -y wazuh-dashboard
if rpm -q wazuh-dashboard &>/dev/null; then
  echo "Package not uninstalled"
  exit 1
else
  echo "Package uninstalled"
fi

echo "==> Checking what the removal kept"
# rpm keeps /etc/wazuh-dashboard. The service user and group are removed, so nothing kept may
# still carry their freed IDs or stay readable by group or others.
if getent passwd wazuh-dashboard >/dev/null || getent group wazuh-dashboard >/dev/null; then
  echo "The wazuh-dashboard user or group was not removed"
  exit 1
fi
orphaned="$(find -P "${config_dir}" \( -nouser -o -nogroup \) -print)"
if [ -n "${orphaned}" ]; then
  echo "Files kept with the ID of the removed user or group:"
  echo "${orphaned}"
  exit 1
fi
for kept_file in "${certs_dir}/dashboard-key.pem" "${keystore_file}" "${operator_file}"; do
  kept_stat="$(stat -c '%U:%G %A' "${kept_file}")" || kept_stat=""
  if [[ "${kept_stat}" != root:root\ -???------ ]]; then
    echo "${kept_file} not handed over to root: ${kept_stat:-<missing>}"
    exit 1
  fi
done
if [ -e "${ca_dir}" ] || [ -e "${config_dir}/export" ] || [ -e /etc/wazuh ]; then
  echo "The removal kept ca/ or export/, or created /etc/wazuh"
  exit 1
fi
if [ ! -f "${indexer_export}/credentials.env" ] || [ ! -f "${manager_export}/credentials.env" ]; then
  echo "The removal touched the peers' export/ directories"
  exit 1
fi
echo "Kept files handed over to root; ca/ and export/ removed"

echo "==> Checking that a reinstall takes the kept files back"
rpm -i "${PACKAGE_NAME}"
for kept_file in "${certs_dir}/dashboard-key.pem" "${keystore_file}"; do
  kept_stat="$(stat -c '%U:%G' "${kept_file}")" || kept_stat=""
  if [ "${kept_stat}" != "root:wazuh-dashboard" ]; then
    echo "${kept_file} not taken back by the reinstall: ${kept_stat:-<missing>}"
    exit 1
  fi
done
echo "Reinstall took the kept files back"

yum remove -y wazuh-dashboard
rm -rf "${config_dir}" /etc/wazuh-indexer /etc/wazuh-manager
