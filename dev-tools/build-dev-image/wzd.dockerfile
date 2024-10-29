# Usage:
# docker buildx build \
#         --platform linux/amd64,linux/arm64 \
#         --build-arg NODE_VERSION=18.19.0 \
#         --build-arg OPENSEARCH_DASHBOARD_VERSION=2.17.1.0 \
#         --build-arg WAZUH_DASHBOARD_BRANCH=change/346-compatibility-with-opensearch-2171 \
#         --build-arg WAZUH_DASHBOARD_SECURITY_BRANCH=change/112-compatibility-with-opensearch-2171 \
#         --build-arg WAZUH_DASHBOARD_REPORTING_BRANCH=change/3-compatibility-with-opensearch-2171 \
#         --build-arg WAZUH_DASHBOARD_PLUGINS_BRANCH=change/7070-compatibility-with-opensearch-2171 \
#         -t quay.io/wazuh/osd-dev:2.17.1 \
#         -f wzd.dockerfile .

ARG NODE_VERSION=18.19.0
FROM node:${NODE_VERSION} AS base
ARG OPENSEARCH_DASHBOARD_VERSION
ARG WAZUH_DASHBOARD_BRANCH
ARG WAZUH_DASHBOARD_SECURITY_BRANCH
ARG WAZUH_DASHBOARD_REPORTING_BRANCH
ARG WAZUH_DASHBOARD_PLUGINS_BRANCH
USER node
RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_BRANCH} https://github.com/wazuh/wazuh-dashboard.git /home/node/kbn
RUN chown node.node /home/node/kbn

WORKDIR /home/node/kbn
RUN yarn osd bootstrap --production

WORKDIR /home/node/kbn/plugins

ADD ./entrypoint.sh /home/node/entrypoint.sh
ADD ./plugins /home/node/plugins
ADD ./wazuh-dashboard-plugins /home/node/wazuh-dashboard-plugins

USER root
RUN chmod +x /home/node/entrypoint.sh
USER node
ENTRYPOINT ["/home/node/entrypoint.sh"]

RUN bash /home/node/entrypoint.sh

RUN mkdir -p /home/node/kbn/data/wazuh/config

FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/kbn /home/node/kbn
WORKDIR /home/node/kbn
