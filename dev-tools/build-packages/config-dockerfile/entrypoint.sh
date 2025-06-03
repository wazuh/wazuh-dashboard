#!/bin/bash
set -e

# Clone wazuh-dashboard
git clone --depth 1 --branch ${WAZUH_DASHBOARDS_BRANCH} https://github.com/wazuh/wazuh-dashboard.git /home/node/wzd
chown node.node /home/node/wzd

## Install dependencies and build wazuh-dashboard

cd /home/node/wzd
yarn osd bootstrap --production
yarn build --linux --skip-os-packages --release

# Clone plugins
cd /home/node/wzd/plugins
git clone --depth 1 --branch ${WAZUH_SECURITY_DASHBOARDS_PLUGIN_BRANCH} https://github.com/wazuh/wazuh-security-dashboards-plugin.git
git clone --depth 1 --branch ${WAZUH_DASHBOARDS_PLUGINS} https://github.com/wazuh/wazuh-dashboard-plugins.git
git clone --depth 1 --branch ${WAZUH_DASHBOARDS_REPORTING_BRANCH} https://github.com/wazuh/wazuh-dashboards-reporting.git

# Build wazuh-security-dashboards-plugin
cd /home/node/wzd/plugins/wazuh-security-dashboards-plugin
yarn
yarn build

# Build wazuh-dashboards-reporting
cd /home/node/wzd/plugins/wazuh-dashboards-reporting
yarn
yarn build

# Move plugins
cd /home/node/wzd/plugins
mv ./wazuh-dashboard-plugins/plugins/main ./wazuh
mv ./wazuh-dashboard-plugins/plugins/wazuh-core ./wazuh-core
mv ./wazuh-dashboard-plugins/plugins/wazuh-check-updates ./wazuh-check-updates

# Build plugins
cd /home/node/wzd/plugins/wazuh
yarn
yarn build

cd /home/node/wzd/plugins/wazuh-core
yarn
yarn build

cd /home/node/wzd/plugins/wazuh-check-updates
yarn
yarn build

# Zip packages
cd /home/node/
mkdir packages
cd /home/node/packages
zip -r -j ./dashboard-package.zip ../wzd/target/opensearch-dashboards-${OPENSEARCH_DASHBOARDS_VERSION}-linux-x64.tar.gz
zip -r -j ./security-package.zip ../wzd/plugins/wazuh-security-dashboards-plugin/build/security-dashboards-${OPENSEARCH_DASHBOARDS_VERSION}.0.zip
zip -r -j ./wazuh-package.zip ../wzd/plugins/wazuh-check-updates/build/wazuhCheckUpdates-${OPENSEARCH_DASHBOARDS_VERSION}.zip ../wzd/plugins/wazuh/build/wazuh-${OPENSEARCH_DASHBOARDS_VERSION}.zip ../wzd/plugins/wazuh-core/build/wazuhCore-${OPENSEARCH_DASHBOARDS_VERSION}.zip
zip -r -j ./reporting-package.zip ../wzd/plugins/wazuh-dashboards-reporting/build/reportsDashboards-${OPENSEARCH_DASHBOARDS_VERSION}.zip

exec "$@"
