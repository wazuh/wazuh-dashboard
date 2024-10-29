plugins=$(cat /home/node/plugins)
wazuh_dashboard_plugins=$(cat /home/node/wazuh-dashboard-plugins)
for plugin in $plugins; do
  echo "Cloning $plugin"
  cd /home/node/kbn/plugins
  if [[ $plugin =~ wazuh* ]]; then

    if [[ $plugin == "wazuh-security-dashboards-plugin" ]]; then
      git clone --depth 1 --branch ${WAZUH_DASHBOARD_SECURITY_BRANCH} https://github.com/wazuh/$plugin.git
    fi

    if [[ $plugin == "wazuh-dashboards-reporting" ]]; then
      git clone --depth 1 --branch ${WAZUH_DASHBOARD_REPORTING_BRANCH} https://github.com/wazuh/$plugin.git
    fi

    if [[ $plugin == "wazuh-dashboard-plugins" ]]; then
      git clone --depth 1 --branch ${WAZUH_DASHBOARD_PLUGINS_BRANCH} https://github.com/wazuh/$plugin.git
      mv $plugin/plugins .
      for wazuh_dashboard_plugin in $wazuh_dashboard_plugins; do
        cd /home/node/kbn/plugins/$wazuh_dashboard_plugin
        yarn install
      done
    fi

  else
    git clone --depth 1 --branch ${OPENSEARCH_DASHBOARD_VERSION} https://github.com/opensearch-project/$plugin.git
  fi
  if [[ $plugin != "wazuh-dashboard-plugins" ]]; then
    cd $plugin
    yarn install
  fi
done
