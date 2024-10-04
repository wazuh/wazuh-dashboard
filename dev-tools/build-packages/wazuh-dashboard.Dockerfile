# Usage: docker build --build-arg NODE_VERSION=18.19.0 --build-arg WAZUH_DASHBOARDS_BRANCH=4.10.0 --build-arg WAZUH_DASHBOARDS_REPORTING_BRANCH=4.10.0 --build-arg WAZUH_DASHBOARDS_PLUGINS=4.10.0 --build-arg WAZUH_SECURITY_DASHBOARDS_PLUGIN_BRANCH=4.10.0 --build-arg OPENSEARCH_DASHBOARDS_VERSION=2.13.0 -t wzd:4.10.0 -f wazuh-dashboard.Dockerfile .

ARG NODE_VERSION
FROM node:${NODE_VERSION} AS base
ARG OPENSEARCH_DASHBOARDS_VERSION
ARG WAZUH_DASHBOARDS_BRANCH
ARG WAZUH_DASHBOARDS_PLUGINS
ARG WAZUH_SECURITY_DASHBOARDS_PLUGIN_BRANCH
ARG WAZUH_DASHBOARDS_REPORTING_BRANCH
ENV OPENSEARCH_DASHBOARDS_VERSION=${OPENSEARCH_DASHBOARDS_VERSION}
USER root
RUN apt-get update && apt-get install -y git zip unzip curl brotli jq
USER node

COPY ./config-dockerfile/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

RUN bash /entrypoint.sh

WORKDIR /home/node/wzd/dev-tools/build-packages/base
RUN ./generate_base.sh -v 4.10.0 -r 1 -a file:///home/node/packages/wazuh-package.zip -s file:///home/node/packages/security-package.zip -b file:///home/node/packages/dashboard-package.zip -rp file:///home/node/packages/reporting-package.zip
WORKDIR /home/node/wzd/dev-tools/build-packages/base/output
RUN cp ./* /home/node/packages/


FROM node:${NODE_VERSION}
USER node
COPY --chown=node:node --from=base /home/node/wzd /home/node/wzd
COPY --chown=node:node --from=base /home/node/packages /home/node/packages
WORKDIR /home/node/wzd
