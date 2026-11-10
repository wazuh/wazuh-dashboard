# Clone the Wazuh security plugin
cd /home/node/app/plugins
git clone --depth 1 --branch ${WAZUH_DASHBOARD_SECURITY_BRANCH} https://github.com/wazuh/wazuh-security-dashboards-plugin.git
cd wazuh-security-dashboards-plugin
yarn install
echo "Building Wazuh security plugin"
yarn build
echo "Copying Wazuh security plugin"
mkdir /home/node/packages/wazuh-security-dashboards-plugin
cp -r build/* /home/node/packages/wazuh-security-dashboards-plugin
