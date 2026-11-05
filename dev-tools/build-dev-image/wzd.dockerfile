# Usage:
# docker build \
#         --build-arg NODE_VERSION=18.19.0 \
#         --build-arg WAZUH_DASHBOARD_BRANCH=4.14.8 \
#         --build-arg WAZUH_DASHBOARD_SECURITY_BRANCH=4.14.8 \
#         --build-arg WAZUH_DASHBOARD_PLUGINS_BRANCH=4.14.8 \
#         -t quay.io/wazuh/osd-dev:4.14.8 \
#         -f wzd.dockerfile .

ARG NODE_VERSION=18.19.0
FROM node:${NODE_VERSION} AS base
ARG WAZUH_DASHBOARD_BRANCH
ARG WAZUH_DASHBOARD_SECURITY_BRANCH
ARG WAZUH_DASHBOARD_PLUGINS_BRANCH
USER node
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_BRANCH} https://github.com/wazuh/wazuh-dashboard.git /home/node/kbn

WORKDIR /home/node/kbn
RUN yarn osd bootstrap --production

WORKDIR /home/node/kbn/plugins

COPY ./install-plugins.sh /home/node/install-plugins.sh
COPY ./plugins /home/node/plugins
RUN bash /home/node/install-plugins.sh

WORKDIR /home/node/kbn
COPY ./warmup-optimizer.sh /home/node/warmup-optimizer.sh
COPY ./warmup-opensearch_dashboards.yml /home/node/warmup-opensearch_dashboards.yml
RUN bash /home/node/warmup-optimizer.sh

FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/kbn /home/node/kbn
WORKDIR /home/node/kbn
COPY --chmod=755 ./entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
