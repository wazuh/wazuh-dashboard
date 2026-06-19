#!/bin/bash
# Runs inside the systemd container started by run_in_systemd_container.sh.
# Tests that installing a 5.x package over a running 4.x installation is blocked.
#
# Usage: deb-test-cross-major-blocked.sh <package-name> <previous-4x-version>

set -euo pipefail

PACKAGE_NAME="$1"
PREVIOUS="$2"

apt-get install -y debhelper tar curl libcap2-bin gnupg apt-transport-https
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
  | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  | tee -a /etc/apt/sources.list.d/wazuh.list
apt-get update
apt-get -y install "wazuh-dashboard=${PREVIOUS}"

systemctl daemon-reload
systemctl enable wazuh-dashboard
systemctl start wazuh-dashboard
if systemctl status wazuh-dashboard | grep -q "active (running)"; then
  echo "Service running"
else
  echo "ERROR: Service not running"
  exit 1
fi

# Attempt 5.x upgrade — MUST fail
set +e
OUTPUT=$(dpkg -i "/test-packages/${PACKAGE_NAME}" 2>&1)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "ERROR: Installation should have been blocked but succeeded"
  exit 1
fi

if echo "$OUTPUT" | grep -F -q "ERROR: Upgrade from Wazuh dashboard versions prior to 5.x is not supported."; then
  echo "TEST: Cross-major upgrade correctly blocked"
  echo "$OUTPUT"
else
  echo "ERROR: Expected block message not found"
  echo "$OUTPUT"
  exit 1
fi
