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

systemctl daemon-reload
systemctl enable wazuh-dashboard
systemctl start wazuh-dashboard
if systemctl status wazuh-dashboard | grep -q "active (running)"; then
  echo "Service running"
else
  echo "Service not running"
  exit 1
fi

apt-get remove --purge wazuh-dashboard -y
if dpkg-query -W -f='${Status}' wazuh-dashboard 2>/dev/null | grep -q "install ok installed"; then
  echo "Package not uninstalled"
  exit 1
else
  echo "Package uninstalled"
fi
