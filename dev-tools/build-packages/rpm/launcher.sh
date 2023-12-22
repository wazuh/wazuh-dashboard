#!/bin/bash

# Wazuh package generator
# Copyright (C) 2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

# Inputs
package=""
version=""
revision="1"
architecture="x86_64"
build_base="yes"
build_docker="yes"

# Constants
rpm_x86_builder="rpm_dashboard_builder_x86"
rpm_builder_dockerfile="${current_path}/docker"

# Paths
current_path="$( cd $(dirname $0) ; pwd -P )"
config_path=$(realpath $current_path/../config)

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
    rm $current_path/docker/x86_64/*.sh

    if [ $exit_code != 0 ]; then
        rm $out_dir/*
        rmdir $out_dir
    fi

    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

build_rpm() {
    container_name="$1"
    dockerfile_path="$2"

    # Validate and download files to build the package
    valid_url='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'

    echo
    echo "Downloading files..."
    echo

    mkdir -p $tmp_dir
    cd $tmp_dir

    if [[ $package =~ $valid_url ]]; then
        if ! curl --output wazuh-dashboard.tar.gz --silent --fail "${package}"; then
            echo "The given URL or Path to the Wazuh Dashboard package is not working: ${package}"
            clean 1
        fi
    else
        echo "The given URL or Path to the Wazuh Dashboard package is not valid: ${package}"
        clean 1
    fi

    echo
    echo Building the package...
    echo

    # Prepare the package
    directory_name=$(tar tf wazuh-dashboard.tar.gz | head -1 | sed 's#/.*##' | sort -u)
    tar -zxf wazuh-dashboard.tar.gz
    rm wazuh-dashboard.tar.gz
    mv $directory_name wazuh-dashboard-base
    mkdir -p wazuh-dashboard-base/etc/services
    cp $config_path/* wazuh-dashboard-base/etc/services
    echo ${version} >wazuh-dashboard-base/VERSION
    tar -czf ./wazuh-dashboard.tar.gz wazuh-dashboard-base

    # Copy the necessary files
    cp ${current_path}/builder.sh ${dockerfile_path}

    # Build the Docker image
    if [[ ${build_docker} == "yes" ]]; then
        docker build -t ${container_name} ${dockerfile_path} || return 1
    fi

    # Build the RPM package with a Docker container

    if [ ! -d "$out_dir" ]; then
      mkdir -p $out_dir
    fi
    volumes="-v ${out_dir}/:/tmp:Z -v ${tmp_dir}/wazuh-dashboard.tar.gz:/opt/wazuh-dashboard.tar.gz"
    docker run -t --rm ${volumes} \
        -v ${current_path}/../..:/root:Z \
        ${container_name} ${architecture} \
        ${revision} ${version} || return 1

    echo "Package $(ls -Art ${out_dir} | tail -n 1) added to ${out_dir}."

    echo
    echo DONE!
    echo

    return 0
}

build() {
    build_name="${rpm_x86_builder}"
    file_path="../${rpm_builder_dockerfile}/${architecture}"
    build_rpm ${build_name} ${file_path} || return 1
    return 0
}

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "    -v, --version <version>        Wazuh version"
    echo "    -p, --package <path>       Set the location of the .tar.gz file containing the Wazuh Dashboard package."
    echo "    -r, --revision <rev>       [Optional] Package revision. By default: 1."
    echo "    -o, --output <path>         [Optional] Set the destination path of package. By default, an output folder will be created."
    echo "    --dont-build-docker        [Optional] Locally built Docker image will be used instead of generating a new one."
    echo "    -h, --help                 Show this help."
    echo
    exit $1
}

main() {
    while [ -n "${1}" ]; do
        case "${1}" in
        "-h" | "--help")
            help 0
            ;;
        "-p" | "--package")
            if [ -n "${2}" ]; then
                package="${2}"
                shift 2
            else
                help 1
            fi
            ;;
        "-v" | "--version")
            if [ -n "${2}" ]; then
                version="${2}"
                shift 2
            else
                help 1
            fi
            ;;
        "-r" | "--revision")
            if [ -n "${2}" ]; then
                revision="${2}"
                shift 2
            else
                help 1
            fi
            ;;
        "--dont-build-docker")
            build_docker="no"
            shift 1
            ;;
        "-o" | "--output")
            if [ -n "${2}" ]; then
                outdir="${2}"
                shift 2
            else
                help 1
            fi
            ;;
        *)
            help 1
            ;;
        esac
    done

    if [ -z "$package" ] | [ -z "$version" ]; then
        help 1
    fi

    build || clean 1

    clean 0
}

main "$@"
