# Usage:
# docker build \
#         --build-arg NODE_VERSION=18.19.0 \
#         --build-arg OPENSEARCH_DASHBOARD_VERSION=2.18.0.0 \
#         --build-arg WAZUH_DASHBOARD_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_SECURITY_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_REPORTING_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_PLUGINS_BRANCH=main \
#         -t quay.io/wazuh/osd-dev:2.18.0 \
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

ADD ./install-plugins.sh /home/node/install-plugins.sh
ADD ./plugins /home/node/plugins
RUN bash /home/node/install-plugins.sh
RUN mkdir -p /home/node/kbn/data/wazuh/config

FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/kbn /home/node/kbn
WORKDIR /home/node/kbn
ADD ./entrypoint.sh /usr/local/bin/entrypoint.sh
USER root
RUN chmod +x /usr/local/bin/entrypoint.sh
USER node
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
