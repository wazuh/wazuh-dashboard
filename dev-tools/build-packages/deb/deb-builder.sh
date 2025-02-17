#!/bin/bash

# Wazuh package builder
# Copyright (C) 2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

set -e

# Script parameters to build the package
target="wazuh-dashboard"
version=$1
revision=$2
architecture=$3
commit_sha=$4
is_production=$5
verbose=$6

directory_base="/usr/share/wazuh-dashboard"

# Paths
current_path="$( cd $(dirname $0) ; pwd -P )"
root_dir="$(git rev-parse --show-toplevel)"
parent_root_dir="$(dirname ${root_dir})"
wazuh_dashboard_plugins_path="${parent_root_dir}/wazuh-dashboard-plugins"
wazuh_security_plugin_path="${parent_root_dir}/wazuh-security-dashboards-plugin"

check_repo_branch() {
  local current_branch="$1"
  local repo_path="$2"

  pushd ${repo_path}
  repo_branch=$(git rev-parse --abbrev-ref HEAD)
  if [ "${current_branch}" != "${repo_branch}" ]; then
    echo "Error: $(basename ${repo_path}) is not on the same branch as the wazuh-dashboard repository."
    exit 1
  fi
  popd
}

check_branch_consistency() {
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  for repo_path in "$@"; do
    check_repo_branch "${current_branch}" "${repo_path}"
  done
}

# Check if the plugin paths exist
check_path_exists() {
  local path="$1"
  if [ ! -d "$path" ]; then
    echo "Error: $path path does not exist: $path"
    exit 1
  fi
}

check_paths_exists() {
  for path in "$@"; do
    check_path_exists "$path"
  done
}

check_paths_exists "${wazuh_dashboard_plugins_path}" "${wazuh_security_plugin_path}"
check_branch_consistency "${wazuh_dashboard_plugins_path}" "${wazuh_security_plugin_path}"

# Folders
tmp_dir="/tmp"
out_dir="/output"
config_path=$tmp_dir/config

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

mkdir -p ${tmp_dir}/wazuh-dashboard-base
cd ${tmp_dir}/wazuh-dashboard-base
log "Extracting base tar.gz..."
tar -zxf ${out_dir}/wazuh-dashboard-$version-$revision-linux-$architecture.tar.gz
log "Preparing the package..."
jq '.wazuh.revision="'${revision}'"' package.json > pkgtmp.json && mv pkgtmp.json package.json
cp $config_path/* .
jq '.version="'${version}'"' VERSION.json > VERSION.tmp && mv VERSION.tmp VERSION.json
pushd ${wazuh_dashboard_plugins_path} && git rev-parse --short HEAD > commit_sha && popd
pushd ${wazuh_security_plugin_path} && git rev-parse --short HEAD > commit_sha && popd
jq '.commit="'${commit_sha}-$(cat ${wazuh_dashboard_plugins_path}/commit_sha)-$(cat ${wazuh_security_plugin_path}/commit_sha)'"' VERSION.json > VERSION.tmp && mv VERSION.tmp VERSION.json
cd ..
tar -czf wazuh-dashboard.tar.gz wazuh-dashboard-base

log "Setting up parameters"
if [ "${architecture}" = "x64" ]; then
  architecture="amd64"
fi
# Build directories
build_dir=/build
pkg_name="${target}-${version}"
pkg_path="${build_dir}/${target}"
source_dir="${pkg_path}/${pkg_name}"
deb_file="${target}_${version}-${revision}_${architecture}.deb"
final_name="${target}_${version}-${revision}_${architecture}_${commit_sha}.deb"

mkdir -p ${source_dir}/debian

# Including spec files
cp -r /usr/local/src/debian/* ${source_dir}/debian/

# Generating directory structure to build the .deb package
cd ${build_dir}/${target} && tar -czf ${pkg_name}.orig.tar.gz "${pkg_name}"

# Configure the package with the different parameters
sed -i "s:VERSION:${version}:g" ${source_dir}/debian/changelog
sed -i "s:RELEASE:${revision}:g" ${source_dir}/debian/changelog
sed -i "s:export INSTALLATION_DIR=.*:export INSTALLATION_DIR=${directory_base}:g" ${source_dir}/debian/rules

# Installing build dependencies
cd ${source_dir}
mk-build-deps -ir -t "apt-get -o Debug::pkgProblemResolver=yes -y"

log "Building the package..."
# Build package
debuild --no-lintian -b -uc -us \
    -eINSTALLATION_DIR="${directory_base}" \
    -eVERSION="${version}" \
    -eREVISION="${revision}"

cd ${pkg_path} && sha512sum ${deb_file} >/${out_dir}/${deb_file}.sha512

if [ "${is_production}" = "no" ]; then
  mv ${pkg_path}/${deb_file} /${out_dir}/${final_name}
  mv /${out_dir}/${deb_file}.sha512 /${out_dir}/${final_name}.sha512
else
  mv ${pkg_path}/${deb_file} /${out_dir}/
fi
