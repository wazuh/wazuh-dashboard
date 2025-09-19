# Clone the Wazuh ML Commons plugin
cd /home/node/app/plugins
git clone --depth 1 --branch ${WAZUH_DASHBOARD_ML_COMMONS_BRANCH} https://github.com/wazuh/wazuh-dashboard-ml-commons.git
cd wazuh-dashboard-ml-commons
yarn install
echo "Building Wazuh ML Commons plugin"
yarn build
echo "Copying Wazuh ML Commons plugin"
mkdir /home/node/packages/wazuh-ml-commons-plugin
cp -r build/* /home/node/packages/wazuh-ml-commons-plugin
