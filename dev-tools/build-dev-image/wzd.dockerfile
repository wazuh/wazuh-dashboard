# Usage:
# docker build \
#         --build-arg NODE_VERSION=22.22.0 \
#         --build-arg OPENSEARCH_DASHBOARD_VERSION=3.6.0.0 \
#         --build-arg WAZUH_DASHBOARD_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_SECURITY_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_REPORTING_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_PLUGINS_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_SECURITY_ANALYTICS_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_ALERTING_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_NOTIFICATIONS_BRANCH=main \
#         -t quay.io/wazuh/osd-dev:3.6.0-5.0.0 \
#         -f wzd.dockerfile .

ARG NODE_VERSION=22.22.0
FROM node:${NODE_VERSION}
ARG OPENSEARCH_DASHBOARD_VERSION
ARG WAZUH_DASHBOARD_BRANCH
ARG WAZUH_DASHBOARD_SECURITY_BRANCH
ARG WAZUH_DASHBOARD_REPORTING_BRANCH
ARG WAZUH_DASHBOARD_PLUGINS_BRANCH
ARG WAZUH_DASHBOARD_SECURITY_ANALYTICS_BRANCH
ARG WAZUH_DASHBOARD_ALERTING_BRANCH
ARG WAZUH_DASHBOARD_NOTIFICATIONS_BRANCH
USER node

# Everything the build needs is copied before the checkout, and the checkout,
# the bootstrap, the plugins and the optimizer warmup share a single layer.
# Runners whose root filesystem is an overlay mount fall back to the vfs
# storage driver, which copies the whole tree on every layer: once
# /home/node/kbn holds node_modules, each extra layer - even a WORKDIR - costs
# about 19 minutes there, while it is free on overlay2.
COPY ./install-plugins.sh /home/node/install-plugins.sh
COPY ./plugins /home/node/plugins
COPY ./warmup-optimizer.sh /home/node/warmup-optimizer.sh
COPY ./warmup-opensearch_dashboards.yml /home/node/warmup-opensearch_dashboards.yml

RUN git clone --depth 1 --branch ${WAZUH_DASHBOARD_BRANCH} https://github.com/wazuh/wazuh-dashboard.git /home/node/kbn \
    && cd /home/node/kbn \
    && yarn osd bootstrap --production \
    && cd /home/node/kbn/plugins \
    && bash /home/node/install-plugins.sh \
    && cd /home/node/kbn \
    && bash /home/node/warmup-optimizer.sh

WORKDIR /home/node/kbn

# A second stage used to exist to drop the intermediate layers, but the build
# above is a single layer now, so it had nothing left to drop and only cost a
# full copy of /home/node/kbn plus a chown over every file in node_modules.
COPY --chmod=755 ./entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
