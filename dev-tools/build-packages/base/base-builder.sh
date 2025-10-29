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
packages_list=(app base security reportPlugin securityAnalytics)
packages_names=("Wazuh plugins" "Wazuh Dashboard" "Security plugin" "Report plugin" "Security analytics plugin")

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
# Replace app category to Alerting app
sed -i -e "s|category:{id:\"opensearch\",label:\"OpenSearch Plugins\",order:2e3}|category:${category_explore}|" $(js-file "alertingDashboards" "plugin")

# Replace app category to Anomaly Detection app
sed -i -e "s|category:{id:\"opensearch\",label:\"OpenSearch Plugins\",order:2e3}|category:${category_explore}|" ./plugins/anomalyDetectionDashboards/target/public/anomalyDetectionDashboards.plugin.js

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
  $(js-file "anomalyDetectionDashboards" "plugin")
  $(js-file "alertingDashboards" "plugin")
  $(js-file "customImportMapDashboards" "plugin")
  $(js-file "indexManagementDashboards" "plugin")
  $(js-file "notificationsDashboards" "plugin")
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
