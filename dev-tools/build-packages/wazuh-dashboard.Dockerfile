# Usage: docker build --build-arg NODE_VERSION=18.19.0 --build-arg OPENSEARCH_DASHBOARDS_VERSION=2.13.0 --build-arg WAZUH_DASHBOARD_VERSION=4.9.0 -t wzd:4.9.0 -f wzd-dev.Dockerfile .

ARG NODE_VERSION
FROM node:${NODE_VERSION} AS base
ARG WAZUH_DASHBOARD_VERSION
ARG OPENSEARCH_DASHBOARDS_VERSION
ENV OPENSEARCH_DASHBOARDS_VERSION=${OPENSEARCH_DASHBOARDS_VERSION}
USER root
RUN apt-get update && apt-get install -y git zip unzip
USER node
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_VERSION} https://github.com/wazuh/wazuh-dashboard.git /home/node/wzd
RUN chown node.node /home/node/wzd

WORKDIR /home/node/wzd
RUN yarn osd bootstrap --production
RUN yarn build --linux --skip-os-packages --release


WORKDIR /home/node/wzd/plugins
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_VERSION} https://github.com/wazuh/wazuh-security-dashboards-plugin.git
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_VERSION} https://github.com/wazuh/wazuh-dashboard-plugins.git
WORKDIR /home/node/wzd/plugins/wazuh-security-dashboards-plugin
RUN yarn
RUN yarn build
WORKDIR /home/node/wzd/plugins
RUN mv ./wazuh-dashboard-plugins/plugins/main ./wazuh
RUN mv ./wazuh-dashboard-plugins/plugins/wazuh-core ./wazuh-core
RUN mv ./wazuh-dashboard-plugins/plugins/wazuh-check-updates ./wazuh-check-updates
WORKDIR /home/node/wzd/plugins/wazuh
RUN yarn
RUN yarn build
WORKDIR /home/node/wzd/plugins/wazuh-core
RUN yarn
RUN yarn build
WORKDIR /home/node/wzd/plugins/wazuh-check-updates
RUN yarn
RUN yarn build

WORKDIR /home/node/
RUN mkdir packages
WORKDIR /home/node/packages
RUN zip -r -j ./dashboard-package.zip ../wazuh-dashboard/target/opensearch-dashboards-2.13.0-linux-x64.tar.gz
RUN zip -r -j ./security-package.zip ../wazuh-dashboard/plugins/wazuh-security-dashboards-plugin/build/security-dashboards-2.13.0.0.zip
RUN zip -r -j ./wazuh-package.zip ../wazuh-dashboard/plugins/wazuh-check-updates/build/wazuhCheckUpdates-2.13.0.zip ../wazuh-dashboard/plugins/main/build/wazuh-2.13.0.zip ../wazuh-dashboard/plugins/wazuh-core/build/wazuhCore-2.13.0.zip

RUN mkdir -p /home/node/wzd/data/wazuh/config

FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/wzd /home/node/wzd
WORKDIR /home/node/wzd
