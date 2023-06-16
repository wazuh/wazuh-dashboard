#!/bin/bash

# Wazuh package generator
# Copyright (C) 2022, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

set -e


current_path="$( cd $(dirname $0) ; pwd -P )"
dockerfile_path="${current_path}/docker"
container_name="dashboard_base_builder"
architecture="x64"
outdir="${current_path}/output"
revision="1"
app_url=""
security_url=""
dashboard_path=""
dashboard_url=""
security_path=""
url=""
version=""

# -----------------------------------------------------------------------------

trap ctrl_c INT

clean() {
    exit_code=$1

    # Clean the files
    rm -rf ${dockerfile_path}/{*.sh,*.tar.xz,*-dashboards-*,*.tar.gz,*.zip}
    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

# -----------------------------------------------------------------------------

build() {

    # Copy the necessary files
    cp ${current_path}/builder.sh ${dockerfile_path}

    # Verify that the necessary fields are provided
    if [ "${dashboard_path}" ];then
        cp ${dashboard_path} ${dockerfile_path}/opensearch-dashboards.tar.gz || { clean 1; }
    elif [ "${dashboard_url}" ];then
        wget -O ${dockerfile_path}/opensearch-dashboards.tar.gz ${dashboard_url} || { clean 1; }
    else
        echo "No dashboard url or path provided"
        clean 1
    fi

    if [ "${security_path}" ];then
        cp ${security_path} ${dockerfile_path}/security-dashboards.zip || { clean 1; }
    elif [ "${security_url}" ];then
        wget -O ${dockerfile_path}/security-dashboards.zip ${security_url} || { clean 1; }
    else
        echo "No security url or path provided"
        clean 1
    fi

    if [ ! "${version}" ];then
        echo "No version provided"
        clean 1
    fi

    if [ "${repository}" ];then
        url="${repository}"
    fi

    # Build the Docker image
    docker build -t ${container_name} ${dockerfile_path} || return 1

    local_file='file://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
    if [[ $url =~ $local_file ]];then
      local_path=`echo $url | sed 's/file:\/\///'`
      file_name=`basename $local_path`
      docker run -t --rm -v ${outdir}/:/tmp/output:Z \
      -v ${current_path}/../..:/root:Z -v ${local_path}:/tmp/${file_name}\
      ${container_name} ${architecture} ${revision} ${url} ${version} || return 1
    else
    docker run -t --rm -v ${outdir}/:/tmp/output:Z \
      -v ${current_path}/../..:/root:Z \
      ${container_name} ${architecture} ${revision} ${url} ${version} || return 1
    fi



    echo "Base file $(ls -Art ${outdir} | tail -n 1) added to ${outdir}."

    return 0
}

# -----------------------------------------------------------------------------

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo "    --app-url <url>            [Optional] Set the repository from where the Wazuh plugin should be downloaded. By default, will be used pre-release."
    echo "    --dashboard-url <url>      Set the repository from where the .tar.gz file containing Wazuh Dashboard should be downloaded. "
    echo "    --dashboard-path <path>    Set the location of the .tar.gz file containing the Wazuh Dashboard."
    echo "    --security-url <url>       Set the repository from where the .zip file containing the Security plugin should be downloaded."
    echo "    --security-path <path>     Set the location of the .zip file containing the security plugin."
    echo "    -v, --version <rev>        Wazuh version"
    echo "    -s, --store <path>         [Optional] Set the destination path of package. By default, an output folder will be created."
    echo "    -r, --revision <rev>       [Optional] Package revision. By default ${revision}"
    echo "    -h, --help                 Show this help."
    echo
    echo "    At least one of the dashboard and one of the security options must be provided"
    exit $1
}

# -----------------------------------------------------------------------------

main() {
    while [ -n "${1}" ]
    do
        case "${1}" in
        "-h"|"--help")
            help 0
            ;;
        "--app-url")
            if [ -n "$2" ]; then
                repository="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "--dashboard-url")
            if [ -n "$2" ]; then
                dashboard_url="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "--security-url")
            if [ -n "$2" ]; then
                security_url="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "--dashboard-path")
            if [ -n "$2" ]; then
                dashboard_path="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "--security-path")
            if [ -n "$2" ]; then
                security_path="$2"
                shift 2
            else
                help 1
            fi
            ;;
        "-s"|"--store")
            if [ -n "${2}" ]; then
                outdir="${2}"
                shift 2
            else
                help 1
            fi
            ;;
            "-v"|"--version")
            if [ -n "${2}" ]; then
                version="${2}"
                shift 2
            else
                help 1
            fi
            ;;
        "-r"|"--revision")
            if [ -n "${2}" ]; then
                revision="${2}"
                shift 2
            else
                help 1
            fi
            ;;
        *)
            help 1
        esac
    done

    build || clean 1

    clean 0
}

main "$@"
