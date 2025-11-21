# Clone the Wazuh security plugin
cd /home/node/app/plugins
git clone --depth 1 --branch ${WAZUH_DASHBOARD_REPORTING_BRANCH} https://github.com/wazuh/wazuh-dashboard-reporting.git
cd wazuh-dashboard-reporting
yarn install
echo "Building Wazuh reporting plugin"
yarn build
echo "Copying Wazuh reporting plugin"
mkdir /home/node/packages/wazuh-dashboard-reporting
cp -r build/* /home/node/packages/wazuh-dashboard-reporting
