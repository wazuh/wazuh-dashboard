# Usage:
# docker build \
#         --build-arg NODE_VERSION=20.18.3 \
#         --build-arg WAZUH_DASHBOARD_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_SECURITY_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_PLUGINS_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_REPORTING_BRANCH=main \
#         --build-arg WAZUH_DASHBOARD_SECURITY_ANALYTICS_BRANCH=main \
#         --build-arg ARCHITECTURE=arm \
#         -t wazuh-packages-to-base:5.0.0 \
#         -f base-packages.Dockerfile .

ARG NODE_VERSION=20.18.3
FROM node:${NODE_VERSION} AS base
ARG ARCHITECTURE='amd'
ARG WAZUH_DASHBOARD_BRANCH
ARG WAZUH_DASHBOARD_SECURITY_BRANCH
ARG WAZUH_DASHBOARD_SECURITY_ANALYTICS_BRANCH
ARG WAZUH_DASHBOARD_PLUGINS_BRANCH
ARG WAZUH_DASHBOARD_REPORTING_BRANCH
ENV OPENSEARCH_DASHBOARDS_VERSION=3.2.0
ENV ENV_ARCHITECTURE=${ARCHITECTURE}
USER root
RUN apt-get update && apt-get install -y jq
USER node
ADD ./clone-plugins.sh /home/node/clone-plugins.sh
ADD ./repositories/wazuh-dashboard.sh /home/node/repositories/wazuh-dashboard.sh
ADD ./repositories/plugins/wazuh-dashboard-security-analytics.sh /home/node/repositories/plugins/wazuh-dashboard-security-analytics.sh
ADD ./repositories/plugins/wazuh-security-dashboards-plugin.sh /home/node/repositories/plugins/wazuh-security-dashboards-plugin.sh
ADD ./repositories/plugins/wazuh-dashboard-reporting.sh /home/node/repositories/plugins/wazuh-dashboard-reporting.sh
ADD ./repositories/plugins/wazuh-dashboard-plugins.sh /home/node/repositories/plugins/wazuh-dashboard-plugins.sh
RUN bash /home/node/clone-plugins.sh

FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/packages /home/node/packages
WORKDIR /home/node/packages
