git clone --depth 1 --branch ${WAZUH_DASHBOARD_BRANCH} https://github.com/wazuh/wazuh-dashboard.git /home/node/app
cd /home/node/app
yarn osd bootstrap --production
echo "Building Wazuh dashboards"
if [ $ENV_ARCHITECTURE == "arm" ]; then
  yarn build-platform --linux-arm --skip-os-packages --release
else
  yarn build-platform --linux --skip-os-packages --release
fi
mkdir /home/node/packages/wazuh-dashboard
echo "Copying Wazuh dashboards"
ls -la /home/node/app/target
cp -r /home/node/app/target/*.tar.gz /home/node/packages/wazuh-dashboard
