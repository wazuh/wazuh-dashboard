plugins=$(cat /home/node/plugins)
base_path_plugins="/home/node/kbn/plugins"
for plugin in $plugins; do
  cd $base_path_plugins
  # Clone the Wazuh security plugin
  if [[ $plugin == "wazuh-security-dashboards-plugin" ]]; then
    git clone --depth 1 --branch ${WAZUH_DASHBOARD_SECURITY_BRANCH} https://github.com/wazuh/$plugin.git
  fi
  # Clone the Wazuh dashboards plugins and move the plugins to the plugins folder
  if [[ $plugin == "wazuh-dashboard-plugins" ]]; then
    git clone --depth 1 --branch ${WAZUH_DASHBOARD_PLUGINS_BRANCH} https://github.com/wazuh/$plugin.git
    wazuh_dashboard_plugins=$(ls $base_path_plugins/$plugin/plugins)
    mv $plugin/plugins/* ./
    for wazuh_dashboard_plugin in $wazuh_dashboard_plugins; do
      cd $base_path_plugins/$wazuh_dashboard_plugin
      GIT_REF="${WAZUH_DASHBOARD_PLUGINS_BRANCH}" yarn install
    done
    cd $base_path_plugins
    rm -rf $plugin
  fi
  if [[ $plugin != "wazuh-dashboard-plugins" ]]; then
    cd $base_path_plugins/$plugin
    yarn install
  fi
done
