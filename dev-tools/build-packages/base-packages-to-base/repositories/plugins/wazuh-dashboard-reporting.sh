# Clone the Wazuh security plugin
cd /home/node/app/plugins
git clone --depth 1 --branch ${WAZUH_DASHBOARD_REPORTING_BRANCH} https://github.com/wazuh/wazuh-dashboards-reporting.git
cd wazuh-dashboards-reporting
yarn install
echo "Building Wazuh reporting plugin"
yarn build
echo "Copying Wazuh reporting plugin"
mkdir /home/node/packages/wazuh-dashboards-reporting
cp -r build/* /home/node/packages/wazuh-dashboards-reporting
