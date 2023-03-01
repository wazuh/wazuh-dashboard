#!/bin/bash

COMPOSE_FILE=dev.yml
COMPOSE_CMD="docker compose -f $COMPOSE_FILE"

export REPO_PATH="../"
export SECURITY_PLUGIN_REPO_PATH="../../wazuh-security-dashboards-plugin"
export WZD_CONFIG_PATH="./config/wzd/opensearch_dashboards.yml"
export NODE_VERSION=$(cat $REPO_PATH/.nvmrc)
export OPENSEARCH_VERSION=$1 

case $2 in
    up)
        $COMPOSE_CMD up -d
        ;;
    down)
        $COMPOSE_CMD down
        ;;
    stop)
        $COMPOSE_CMD stop
        ;;
    *)
        echo "Usage: $0 {up|down|stop}"
        exit 1
esac
