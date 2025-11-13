#!/bin/bash
set -euo pipefail

RETRY_MAX_ATTEMPTS=${RETRY_MAX_ATTEMPTS:-3}
RETRY_DELAY_SECONDS=${RETRY_DELAY_SECONDS:-15}

source /usr/local/lib/wazuh/run-with-retry.sh

base_path_plugins="/home/node/app/plugins"
base_path_repositories_scripts="/home/node/repositories"
base_path_repositories_plugins_scripts="/home/node/repositories/plugins"
plugins=$(ls $base_path_repositories_plugins_scripts)

mkdir -p /home/node/packages
echo "Cloning Wazuh dashboard"
source $base_path_repositories_scripts/wazuh-dashboard.sh

for plugin in $plugins; do
  echo "Cloning $plugin"
  source $base_path_repositories_plugins_scripts/$plugin
done
