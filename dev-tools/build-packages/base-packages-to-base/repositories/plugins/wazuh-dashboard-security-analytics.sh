# Clone the Wazuh Security Analytics plugin
cd /home/node/app/plugins
git clone --depth 1 --branch ${WAZUH_DASHBOARD_SECURITY_ANALYTICS_BRANCH} https://github.com/wazuh/wazuh-dashboard-security-analytics.git
cd wazuh-dashboard-security-analytics
yarn install
echo "Building Wazuh Security Analytics plugin"
yarn build
echo "Copying Wazuh Security Analytics plugin"
mkdir /home/node/packages/wazuh-security-analytics-plugin
cp -r build/* /home/node/packages/wazuh-security-analytics-plugin