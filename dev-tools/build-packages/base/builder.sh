#!/bin/bash

# Wazuh dashboard base builder
# Copyright (C) 2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

set -e

# Script parameters to build the package
architecture="$1"
revision="$2"
repository="$3"
version="$4"
base_dir=/opt/wazuh-dashboard-base

# -----------------------------------------------------------------------------

if [ -z "${revision}" ]; then
    revision="1"
fi

if [ "${architecture}" = "x86_64" ] || [ "${architecture}" = "amd64" ]; then
    architecture="x64"
fi

wazuh_minor=$(echo ${version} | cut -c1-3)

# Obtain Wazuh plugin URL
if [ "${repository}" ];then
    valid_url='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
    if [[ $repository =~ $valid_url ]];then
    local_file='file://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
      if [[ $repository =~ $local_file ]];then
        local_path=`echo $repository | sed 's/file:\/\///'`
        file_name=`basename $local_path`
        url="file:///tmp/${file_name}"
      else
        url="${repository}"
      fi
        if ! curl --output /dev/null --silent --head --fail "${url}"; then
            echo "The given URL to download the Wazuh plugin zip does not exist: ${url}"
            exit 1
        fi
    else
        url="https://packages-dev.wazuh.com/${repository}/ui/dashboard/wazuh-${version}-${revision}.zip"
    fi
else
    url="https://packages-dev.wazuh.com/pre-release/ui/dashboard/wazuh-${version}-${revision}.zip"
fi

# -----------------------------------------------------------------------------

mkdir -p /tmp/output
cd /opt
mv opensearch-dashboards* "${base_dir}"
cd "${base_dir}"

# Fix ambiguous shebangs
grep -rnwl './node_modules/' -e '#!/usr/bin/env python$' | xargs -I {} sed -i 's/#!\/usr\/bin\/env python/#!\/usr\/bin\/env python3/g' {}
grep -rnwl './node_modules/' -e '#!/usr/bin/python$' | xargs -I {} sed -i 's/#!\/usr\/bin\/python/#!\/usr\/bin\/python3/g' {}

# Remove unnecessary files and set up configuration
rm -rf ./plugins/*
cp -r /root/build-packages/base/files/etc ./

# Add VERSION file
 echo ${version} > ./VERSION

# Add exception for wazuh plugin install
 wazuh_plugin="if (plugin.includes(\'wazuh\')) {\n    return plugin;\n  } else {\n    return \`\${LATEST_PLUGIN_BASE_URL}\/\${version}\/latest\/\${platform}\/\${arch}\/tar\/builds\/opensearch-dashboards\/plugins\/\${plugin}-\${version}.zip\`;\n  }"
 sed -i "s|return \`\${LATEST_PLUGIN_BASE_URL}\/\${version}\/latest\/\${platform}\/\${arch}\/tar\/builds\/opensearch-dashboards\/plugins\/\${plugin}-\${version}.zip\`;|$wazuh_plugin|" ./src/cli_plugin/install/settings.js

 # Generate build number for package.json
 curl -sO ${url}
 unzip wazuh*.zip 'opensearch-dashboards/wazuh/package.json'
 build_number=$(jq -r '.version' ./opensearch-dashboards/wazuh/package.json | tr -d '.')$(jq -r '.revision' ./opensearch-dashboards/wazuh/package.json)
 rm -rf ./opensearch-dashboards
 rm -f ./wazuh*.zip
 jq ".build.number=${build_number}" ./package.json > ./package.json.tmp
 mv ./package.json.tmp ./package.json

# Install security plugin
/bin/bash ./bin/opensearch-dashboards-plugin install file:/opt/security-dashboards.zip --allow-root

# Set up permissions
 find -type d -exec chmod 750 {} \;
 find -type f -perm 644 -exec chmod 640 {} \;
 find -type f -perm 755 -exec chmod 750 {} \;
 find -type f -perm 744 -exec chmod 740 {} \;


# Base output
cd /opt
tar -cJf wazuh-dashboard-base-"${version}"-"${revision}"-linux-${architecture}.tar.xz wazuh-dashboard-base
cp wazuh-dashboard-base-"${version}"-"${revision}"-linux-${architecture}.tar.xz /tmp/output/
