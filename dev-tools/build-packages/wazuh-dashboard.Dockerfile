# Usage: docker build --build-arg NODE_VERSION=18.19.0 --build-arg WAZUH_DASHBOARDS_BRANCH=4.9.2 --build-arg WAZUH_DASHBOARDS_PLUGINS=4.9.2 --build-arg WAZUH_SECURITY_DASHBOARDS_PLUGIN_BRANCH=4.9.2 --build-arg OPENSEARCH_DASHBOARDS_VERSION=2.13.0 -t wzd:4.9.2 -f wazuh-dashboard.Dockerfile .

ARG NODE_VERSION
FROM node:${NODE_VERSION} AS base
ARG OPENSEARCH_DASHBOARDS_VERSION
ARG WAZUH_DASHBOARDS_BRANCH
ARG WAZUH_DASHBOARDS_PLUGINS
ARG WAZUH_SECURITY_DASHBOARDS_PLUGIN_BRANCH
ENV OPENSEARCH_DASHBOARDS_VERSION=${OPENSEARCH_DASHBOARDS_VERSION}
USER root
RUN apt-get update && apt-get install -y git zip unzip curl brotli jq
USER node
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARDS_BRANCH} https://github.com/wazuh/wazuh-dashboard.git /home/node/wzd
RUN chown node.node /home/node/wzd

WORKDIR /home/node/wzd
RUN yarn osd bootstrap --production
RUN yarn build --linux --skip-os-packages --release


WORKDIR /home/node/wzd/plugins
RUN git clone --depth 1 --branch ${WAZUH_SECURITY_DASHBOARDS_PLUGIN_BRANCH} https://github.com/wazuh/wazuh-security-dashboards-plugin.git
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARDS_PLUGINS} https://github.com/wazuh/wazuh-dashboard-plugins.git
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
RUN zip -r -j ./dashboard-package.zip ../wzd/target/opensearch-dashboards-${OPENSEARCH_DASHBOARDS_VERSION}-linux-x64.tar.gz
RUN zip -r -j ./security-package.zip ../wzd/plugins/wazuh-security-dashboards-plugin/build/security-dashboards-${OPENSEARCH_DASHBOARDS_VERSION}.0.zip
RUN zip -r -j ./wazuh-package.zip ../wzd/plugins/wazuh-check-updates/build/wazuhCheckUpdates-${OPENSEARCH_DASHBOARDS_VERSION}.zip ../wzd/plugins/wazuh/build/wazuh-${OPENSEARCH_DASHBOARDS_VERSION}.zip ../wzd/plugins/wazuh-core/build/wazuhCore-${OPENSEARCH_DASHBOARDS_VERSION}.zip
WORKDIR /home/node/wzd/dev-tools/build-packages/base
RUN ./generate_base.sh -v 4.9.2 -r 1 -a file:///home/node/packages/wazuh-package.zip -s file:///home/node/packages/security-package.zip -b file:///home/node/packages/dashboard-package.zip
WORKDIR /home/node/wzd/dev-tools/build-packages/base/output
RUN cp ./* /home/node/packages/


FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/wzd /home/node/wzd
COPY --chown=node:node --from=base /home/node/packages /home/node/packages
WORKDIR /home/node/wzd
