# Usage: docker build --build-arg NODE_VERSION=18.19.0 --build-arg WAZUH_DASHBOARD_VERSION=4.9.0 -t wzd:4.9.0 -f wzd-dev.Dockerfile .

ARG NODE_VERSION
FROM node:${NODE_VERSION} AS base
ARG WAZUH_DASHBOARD_VERSION
USER node
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_VERSION} https://github.com/wazuh/wazuh-dashboard.git /home/node/kbn
RUN chown node.node /home/node/kbn

WORKDIR /home/node/kbn
RUN yarn osd bootstrap --production
RUN yarn build --linux --skip-os-packages --release


WORKDIR /home/node/kbn/plugins
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_VERSION} https://github.com/wazuh/wazuh-security-dashboards-plugin.git
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_VERSION} https://github.com/wazuh/wazuh-dashboard-plugins.git
WORKDIR /home/node/kbn/plugins/wazuh-security-dashboards-plugin
RUN yarn
RUN yarn build
WORKDIR /home/node/kbn/plugins
RUN mv ./wazuh-dashboard-plugins/plugins/main ./wazuh
RUN mv ./wazuh-dashboard-plugins/plugins/wazuh-core ./wazuh-core
RUN mv ./wazuh-dashboard-plugins/plugins/wazuh-check-updates ./wazuh-check-updates
WORKDIR /home/node/kbn/plugins/wazuh
RUN yarn
RUN yarn build
WORKDIR /home/node/kbn/plugins/wazuh-core
RUN yarn
RUN yarn build
WORKDIR /home/node/kbn/plugins/wazuh-check-updates
RUN yarn
RUN yarn build

RUN mkdir -p /home/node/kbn/data/wazuh/config

FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/kbn /home/node/kbn
WORKDIR /home/node/kbn
