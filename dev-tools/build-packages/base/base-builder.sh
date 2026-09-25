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

source /usr/local/lib/wazuh/run-with-retry.sh

if [ "$verbose" = "debug" ]; then
  set -x
fi

# Folders
tmp_dir="/tmp"
out_dir="/output"
config_path="${tmp_dir}/config"
applications_dir="${tmp_dir}/applications"
base_dir="${tmp_dir}/base"

log() {
  if [ "$verbose" = "info" ] || [ "$verbose" = "debug" ]; then
    echo "$@"
  fi
}

clean() {
  exit_code=$?
  # Clean the files
  rm -rf "${applications_dir}" "${base_dir}"
  trap '' EXIT
  exit ${exit_code}
}

trap clean INT
trap clean EXIT

js-file() {
  echo "./plugins/$1/target/public/$1.$2.js"
}

# Paths
current_path="$(
  cd $(dirname $0)
  pwd -P
)"

# -----------------------------------------------------------------------------
cd $tmp_dir

rm -rf "${applications_dir}" "${base_dir}"
mkdir -p "${applications_dir}" "${base_dir}"

log
log "Extracting packages"
log

packages_list=(app base security reportPlugin securityAnalytics alerting notifications)
packages_names=("Wazuh plugins" "Wazuh Dashboard" "Security plugin" "Report plugin" "Security analytics plugin" "Alerting plugin" "Notifications plugin")

for i in "${!packages_list[@]}"; do
  package_var="${packages_list[$i]}"
  package_name="${packages_names[$i]}"
  if [[ "$package_var" == "base" ]]; then
    wzd_package_name=$(unzip -l "packages/${package_var}.zip" | awk 'NR==4 {print $4}')
    unzip -o -q "packages/${package_var}.zip" -d "${base_dir}"
  else
    unzip -o -q "packages/${package_var}.zip" -d "${applications_dir}"
  fi
done

cd "${base_dir}"

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
  if ! run_with_retry bin/opensearch-dashboards-plugin install "${install}" --allow-root >/dev/null; then
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

# Replace app category to Maps app
sed -i -e "s|category:{id:\"opensearch\",label:\"OpenSearch Plugins\",order:2e3}|category:${category_explore}|" $(js-file "customImportMapDashboards" "plugin")

# Replace app category to Index Management app
sed -i -e "s|defaultMessage:\"Management\"|${category_label_indexer_management}|g" $(js-file "indexManagementDashboards" "plugin")

log
log "Recreating plugin files"
log

# Generate compressed files
files_to_recreate=(
  $(js-file "customImportMapDashboards" "plugin")
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
log "Adding credentials resolver"
log

# resolve-credentials is the dashboard's own half of the credential ladder and
# lives in this repository. Its shared half, wazuh-credentials.sh, is owned by
# wazuh-installation-assistant and downloaded here, at build time only, so
# maintainer scripts and the unit never reach the network. There is no bundled
# fallback: a failed download or a checksum mismatch fails the build.
#
# WAZUH_CREDENTIALS_LIB_REFS is the ordered list of refs to try, computed by
# build-packages.sh from the ref being built (a tag build lists only its tag).
# The first ref that downloads wins; a 404 falls through to the next one, and
# curl retries transient failures on each.
credentials_lib_base="https://raw.githubusercontent.com/wazuh/wazuh-installation-assistant"
credentials_lib_ref=""
credentials_lib_url=""

install -m 750 "${tmp_dir}/credentials/resolve-credentials.sh" bin/resolve-credentials
mkdir -p lib
for ref in ${WAZUH_CREDENTIALS_LIB_REFS:-${version}}; do
  url="${credentials_lib_base}/${ref}/credentials_lib/wazuh-credentials.sh"
  log "Downloading the shared credentials library from ${url}"
  if curl --output lib/wazuh-credentials.sh --silent --show-error --fail \
    --retry 3 --retry-delay 5 --retry-connrefused "${url}"; then
    credentials_lib_ref="${ref}"
    credentials_lib_url="${url}"
    break
  fi
  log "The shared credentials library is not available at ${ref} (${url})"
done
if [ -z "${credentials_lib_ref}" ]; then
  echo "Failed to download the shared credentials library from any of: ${WAZUH_CREDENTIALS_LIB_REFS:-${version}}"
  rm -f lib/wazuh-credentials.sh
  exit 1
fi
if [ -n "${WAZUH_CREDENTIALS_LIB_SHA256}" ] &&
  ! echo "${WAZUH_CREDENTIALS_LIB_SHA256}  lib/wazuh-credentials.sh" | sha256sum --check --status -; then
  echo "Checksum mismatch for the shared credentials library from ${credentials_lib_ref} (${credentials_lib_url})"
  rm -f lib/wazuh-credentials.sh
  exit 1
fi
chmod 640 lib/wazuh-credentials.sh
log "Shared credentials library from ${credentials_lib_ref} (${credentials_lib_url}): $(sha256sum lib/wazuh-credentials.sh | cut -d' ' -f1)"

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
