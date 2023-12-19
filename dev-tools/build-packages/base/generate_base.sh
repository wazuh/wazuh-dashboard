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
app=""
base=""
revision="1"
security=""
version=""

# Paths
current_path="$( cd $(dirname $0) ; pwd -P )"
config_path=$(realpath $current_path/../../../config)

# Folders
out_dir="${current_path}/output"
tmp_dir="${current_path}/tmp"

trap ctrl_c INT

clean() {
    exit_code=$1
    echo
    echo "Cleaning temporary files..."
    echo
    # Clean the files
    rm -r $tmp_dir

    if [ $exit_code != 0 ]; then
        rm $out_dir/*.tar.gz
        rmdir $out_dir
    fi

    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

# -----------------------------------------------------------------------------

build() {
    # Validate and download files to build the package
    valid_url='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
    echo
    echo "Downloading plugins..."
    echo
    mkdir -p $tmp_dir
    cd $tmp_dir
    mkdir -p applications
    mkdir -p dashboards
    if [[ $app =~ $valid_url ]]; then
        if ! curl --output applications/app.zip --silent --fail "${app}"; then
            echo "The given URL or Path to the Wazuh Apps is not working: ${app}"
            clean 1
        else
            echo "Extracting applications from app.zip"
            unzip -q applications/app.zip -d applications
            rm applications/app.zip
        fi
    else
        echo "The given URL or Path to the Wazuh App is not valid: ${app}"
        clean 1
    fi

    echo
    echo "Downloading dashboards..."
    echo

    if [[ $base =~ $valid_url ]]; then
        if [[ $base =~ .*\.zip ]]; then
            if ! curl --output wazuh-dashboard.zip --silent --fail "${base}"; then
                echo "The given URL or Path to the Wazuh Dashboard base is not working: ${base}"
                clean 1
            else
                echo "Extracting Wazuh Dashboard base"
                unzip -q wazuh-dashboard.zip -d ./dashboards/
                rm wazuh-dashboard.zip
                mv ./dashboards/$(ls ./dashboards) wazuh-dashboard.tar.gz
            fi
        else
            if ! curl --output wazuh-dashboard.tar.gz --silent --fail "${base}"; then
                echo "The given URL or Path to the Wazuh Dashboard base is not working: ${base}"
                clean 1
            fi
        fi
    else
        echo "The given URL or Path to the Wazuh Dashboard base is not valid: ${base}"
        clean 1
    fi

    echo
    echo "Downloading security plugin..."
    echo

    if [[ $security =~ $valid_url ]]; then
        if ! curl --output applications/security.zip --silent --fail "${security}"; then
            echo "The given URL or Path to the Wazuh Security Plugin is not working: ${security}"
            clean 1
        else
            echo "Extracting Security application"
            unzip -q applications/security.zip -d applications
            rm applications/security.zip
        fi
    else
        echo "The given URL or Path to the Wazuh Security Plugin is not valid: ${security}"
        clean 1
    fi

    tar -zxf wazuh-dashboard.tar.gz
    directory_name=$(tar tf wazuh-dashboard.tar.gz | head -1 | sed 's#/.*##' | sort -u)
    working_dir="wazuh-dashboard-$version-$revision-linux-x64"
    mv $directory_name $working_dir
    cd $working_dir

    echo
    echo Building the package...
    echo

    # Install plugins
    bin/opensearch-dashboards-plugin install alertingDashboards
    bin/opensearch-dashboards-plugin install customImportMapDashboards
    bin/opensearch-dashboards-plugin install ganttChartDashboards
    bin/opensearch-dashboards-plugin install indexManagementDashboards
    bin/opensearch-dashboards-plugin install notificationsDashboards
    bin/opensearch-dashboards-plugin install reportsDashboards
    # Install Wazuh apps and Security app
    plugins=$(ls $tmp_dir/applications)
    echo $plugins
    for plugin in $plugins; do
        echo $plugin
        if [[ $plugin =~ .*\.zip ]]; then
            bin/opensearch-dashboards-plugin install file:../applications/$plugin
        fi
    done

    # Enable the default configuration (renaming)
    cp $config_path/opensearch_dashboards.prod.yml config/opensearch_dashboards.yml
    cp $config_path/node.options.prod config/node.options

    # TODO: investigate to remove this if possible
    # Fix ambiguous shebangs (necessary for RPM building)
    grep -rnwl './node_modules/' -e '#!/usr/bin/env python$' | xargs -I {} sed -i 's/#!\/usr\/bin\/env python/#!\/usr\/bin\/env python3/g' {}
    grep -rnwl './node_modules/' -e '#!/usr/bin/python$' | xargs -I {} sed -i 's/#!\/usr\/bin\/python/#!\/usr\/bin\/python3/g' {}

    # Compress
    echo
    echo Compressing the package...
    echo
    cd ..
    if [ ! -d "$out_dir" ]; then
      mkdir -p $out_dir
    fi
    tar -czf $out_dir/$working_dir.tar.gz $working_dir

    echo
    echo DONE!
    echo
    clean 0
}

# -----------------------------------------------------------------------------

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo "    -a, --app <url/path>          Set the location of the .zip file containing the Wazuh plugin."
    echo "    -b, --base <url/path>         Set the location of the .tar.gz file containing the base wazuh-dashboard build."
    echo "    -s, --security <url/path>     Set the location of the .zip file containing the wazuh-security-dashboards-plugin."
    echo "    -v, --version <version>       Set the version of this build."
    echo "    -r, --revision <revision>      [Optional] Set the revision of this build. By default, it is set to 1."
    echo "    -o, --output <path>           [Optional] Set the destination path of package. By default, an output folder will be created."
    echo "    -h, --help                    Show this help."
    echo
    exit $1
}

# -----------------------------------------------------------------------------

main() {
    while [ -n "${1}" ]; do
        case "${1}" in
        "-h" | "--help")
            help 0
            ;;
        "-a" | "--app")
            if [ -n "$2" ]; then
                app="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "-s" | "--security")
            if [ -n "${2}" ]; then
                security="${2}"
                shift 2
            else
                help 0
            fi
            ;;
        "-b" | "--base")
            if [ -n "${2}" ]; then
                base="${2}"
                shift 2
            else
                help 0
            fi
            ;;
        "-v" | "--version")
            if [ -n "${2}" ]; then
                version="${2}"
                shift 2
            else
                help 0
            fi
            ;;
        "-r" | "--revision")
            if [ -n "${2}" ]; then
                revision="${2}"
                shift 2
            fi
            ;;
        "-o" | "--output")
            if [ -n "${2}" ]; then
                output="${2}"
                shift 2
            fi
            ;;
        *)

            help 1
            ;;
        esac
    done

    if [ -z "$app" ] | [ -z "$base" ] | [ -z "$security" ] | [ -z "$version" ]; then
        help 1
    fi

    build || exit 1

    exit 0
}

main "$@"
