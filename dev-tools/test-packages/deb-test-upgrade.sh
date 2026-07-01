#!/bin/bash
# Runs inside the systemd container started by run_in_systemd_container.sh.
# Tests that a same-major upgrade installs correctly and the service restarts.
#
# Usage: deb-test-upgrade.sh <package-name> <previous-version> <current-version>

set -euo pipefail

PACKAGE_NAME="$1"
PREVIOUS="$2"
VERSION="$3"

apt-get update
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

dpkg -i "/test-packages/deb/${PACKAGE_NAME}"
systemctl restart wazuh-dashboard

if dpkg -s wazuh-dashboard | grep '^Version:' | grep -q "${VERSION}"; then
  echo "Package upgraded"
else
  echo "Package not upgraded"
  exit 1
fi

if systemctl status wazuh-dashboard | grep -q "active (running)"; then
  echo "Service running"
else
  echo "Service not running"
  exit 1
fi
