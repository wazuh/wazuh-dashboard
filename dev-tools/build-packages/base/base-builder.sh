#!/bin/bash

# Wazuh package generator
# Copyright (C) 2022, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

set -e

# Inputs
version="$1"
revision="$2"
architecture="$3"
verbose="$4"

if [ "$verbose" = "debug" ]; then
  set -x
fi

trap clean INT
trap clean EXIT

log() {
  if [ "$verbose" = "info" ] || [ "$verbose" = "debug" ]; then
    echo "$@"
  fi
}

clean() {
  exit_code=$?
  # Clean the files
  rm -rf ${tmp_dir}/*
  trap '' EXIT
  exit ${exit_code}
}

js-file() {
  echo "./plugins/$1/target/public/$1.$2.js"
}

assistant_dashboard_whitelabeling() {
  local plugin_name="assistantDashboards"
	local ASSISTANT_DASHBOARD_CHUNK_FILE=$(js-file $plugin_name "chunk.10")
	local ASSISTANT_DASHBOARD_PLUGIN_FILE=$(js-file $plugin_name "plugin")

	local OLD_IMAGE="base64,PHN2ZyB3aWR0aD0iNDAiIGhlaWdodD0iNDAiIHZpZXdCb3g9IjAgMCA0MCA0MCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICAgIDxwYXRoIGZpbGwtcnVsZT0iZXZlbm9kZCIgY2xpcC1ydWxlPSJldmVub2RkIiBkPSJNMzAuODMzMyAzOS44NTlDMzEuODk2MiAzOS40Mzk4IDMxLjg2OCAzOC4xMTU5IDMxLjg2OCAzNy4wMjk0VjMyLjY2NjZIMzQuMjg1N0MzNy40NDE3IDMyLjY2NjYgNDAgMzAuMjUzOSA0MCAyNy4yNzc1VjcuMzg5MTRDND.*InVzZXJTcGFjZU9uVXNlIj4KICAgIDxzdG9wIHN0b3AtY29sb3I9IiMwMEEzRTAiLz4KICAgIDxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iIzAwQTNFMCIgc3RvcC1vcGFjaXR5PSIwIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogICAgPC9kZWZzPgo8L3N2Zz4="

	local NEW_IMAGE="base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz4KPHN2ZyB2ZXJzaW9uPSIxLjEiIGlkPSJMYXllcl8xIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB4PSIwcHgiIHk9IjBweCIKCSB2aWV3Qm94PSIwIDAgNTEyIDUxMiIgc3R5bGU9ImVuYWJsZS1iYWNrZ3JvdW5kOm5ldyAwIDAgNTEyIDUxMjsiIHhtbDpzcGFjZT0icHJlc2VydmUiPgo8Zz4KCTxwYXRoIGZpbGw9IiMwMDZCQjQiIGQ9Ik00MDQuNSwyMS4yVjBoLTI5N0M0OC45LDAsMS40LDQ3LjUsMS40LDEwNi4xdjE2OS43YzAsNTguNiw0Ny41LDEwNi4xLDEwNi4xLDEwNi4xaDI0Ni45TDUxMC42LDUxMlYxMDYuMQoJCUM1MTAuNiw0Ny41LDQ2My4xLDAsNDA0LjUsMFYyMS4ydjIxLjJjMzUuMSwwLjEsNjMuNiwyOC41LDYzLjYsNjMuNnYzMTUuM2wtOTguNC04MkgxMDcuNWMtMzUuMS0wLjEtNjMuNi0yOC41LTYzLjYtNjMuNmwwLTE2OS43CgkJYzAuMS0zNS4xLDI4LjUtNjMuNiw2My42LTYzLjZoMjk3VjIxLjJ6IE00MDQuNSwxMjcuM0gxMjguN3Y0Mi40aDI3NS44VjEyNy4zeiBNNDA0LjUsMjEyLjFIMjEzLjZ2NDIuNGgxOTAuOVYyMTIuMXoiLz4KPC9nPgo8L3N2Zz4K"

	sed -i -e "s|OpenSearch Assistant|Dashboard assistant|g" $ASSISTANT_DASHBOARD_CHUNK_FILE
	sed -i -e "s|OpenSearch Assistant|Dashboard assistant|g" $ASSISTANT_DASHBOARD_PLUGIN_FILE
	sed -i -e "s|he Dashboard assistant|he dashboard assistant|g" $ASSISTANT_DASHBOARD_PLUGIN_FILE

	sed -i -e "s|$OLD_IMAGE|$NEW_IMAGE|" $ASSISTANT_DASHBOARD_PLUGIN_FILE
}

# Paths
current_path="$(
  cd $(dirname $0)
  pwd -P
)"

# Folders
tmp_dir="/tmp"
out_dir="/output"
config_path=$tmp_dir/config

# -----------------------------------------------------------------------------
cd $tmp_dir

log
log "Extracting packages"
log

mkdir -p applications
mkdir -p base
packages_list=(app base security)
packages_names=("Wazuh plugins" "Wazuh Dashboard" "Security plugin")

for i in "${!packages_list[@]}"; do
  package_var="${packages_list[$i]}"
  package_name="${packages_names[$i]}"
  if [[ "$package_var" == "base" ]]; then
    wzd_package_name=$(unzip -l "packages/${package_var}.zip" | awk 'NR==4 {print $4}')
    unzip -o -q "packages/${package_var}.zip" -d base
  else
    unzip -o -q "packages/${package_var}.zip" -d applications
  fi
done

cd base

log
log "Installing plugins"
log

tar -zxf $wzd_package_name
directory_name=$(ls -td */ | head -1)
cd $directory_name
plugins=$(ls $tmp_dir/applications)' '$(cat $current_path/plugins)
for plugin in $plugins; do
  if [[ $plugin =~ .*\.zip ]]; then
    install="file://${tmp_dir}/applications/${plugin}"
  else
    install=$plugin
  fi
  log "Installing ${plugin} plugin"
  if ! bin/opensearch-dashboards-plugin install $install --allow-root 2>&1 >/dev/null; then
    echo "Plugin ${plugin} installation failed"
    exit 1
  fi
  log "Plugin ${plugin} installed successfully"
  log
done

log
log "Replacing application categories"
log

category_explore='{id:"explore",label:"Explore",order:100,euiIconType:"search"}'
category_label_indexer_management='defaultMessage:"Indexer management"'

old_category_notifications='category:(_core$chrome=core.chrome)!==null&&_core$chrome!==void 0&&(_core$chrome=_core$chrome.navGroup)!==null&&_core$chrome!==void 0&&_core$chrome.getNavGroupEnabled()?undefined:_public.DEFAULT_APP_CATEGORIES.management'
# Replace app category to Reporting app
sed -i -e "s|category:{id:\"opensearch\",label:_i18n.i18n.translate(\"opensearch.reports.categoryName\",{defaultMessage:\"OpenSearch Plugins\"}),order:2e3}|category:${category_explore}|" $(js-file "reportsDashboards" "plugin")

# Replace app category to Alerting app
sed -i -e "s|category:{id:\"opensearch\",label:\"OpenSearch Plugins\",order:2e3}|category:${category_explore}|" $(js-file "alertingDashboards" "plugin")

# Replace app category to Maps app
sed -i -e "s|category:{id:\"opensearch\",label:\"OpenSearch Plugins\",order:2e3}|category:${category_explore}|" $(js-file "customImportMapDashboards" "plugin")

# Replace app category to Notifications app
sed -i -e "s|${old_category_notifications}|category:${category_explore}|" $(js-file "notificationsDashboards" "plugin")

# Replace app category to Index Management app
sed -i -e "s|defaultMessage:\"Management\"|${category_label_indexer_management}|g" $(js-file "indexManagementDashboards" "plugin")

log
log "Recreating plugin files"
log

# Generate compressed files
files_to_recreate=(
  $(js-file $plugin_name "chunk.10")
  $(js-file $plugin_name "plugin")
  $(js-file "reportsDashboards" "plugin")
  $(js-file "alertingDashboards" "plugin")
  $(js-file "customImportMapDashboards" "plugin")
  $(js-file "notificationsDashboards" "plugin")
  $(js-file "indexManagementDashboards" "plugin")
)

for value in "${files_to_recreate[@]}"; do
  gzip -c -9 "$value" >"$value.gz"
  brotli -c -q 11 -f "$value" >"$value.br"
done

log
log "Adding configuration files"
log

cp -f $config_path/opensearch_dashboards.prod.yml config/opensearch_dashboards.yml
cp -f $config_path/node.options.prod config/node.options

log
log "Fixing shebangs"
log
# TODO: investigate to remove this if possible
# Fix ambiguous shebangs (necessary for RPM building)
grep -rnwl './node_modules/' -e '#!/usr/bin/env python$' | xargs -I {} sed -i 's/#!\/usr\/bin\/env python/#!\/usr\/bin\/env python3/g' {}
grep -rnwl './node_modules/' -e '#!/usr/bin/python$' | xargs -I {} sed -i 's/#!\/usr\/bin\/python/#!\/usr\/bin\/python3/g' {}

log
log "Compressing final package"
log

mkdir -p $out_dir
cp ${current_path}/VERSION.json .
tar -czf $out_dir/wazuh-dashboard-$version-$revision-linux-$architecture.tar.gz *

log Done!
