#!/bin/bash

# Wazuh package generator
# Copyright (C) 2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

current_path="$( cd $(dirname $0) ; pwd -P )"
architecture="amd64"
outdir="${current_path}/output"
revision="1"
build_docker="yes"
deb_amd64_builder="deb_dashboard_builder_amd64"
deb_builder_dockerfile="${current_path}/docker"
base_cmd=""
url=""
build_base="yes"
security_url=""
dashboard_path=""
dashboard_url=""
security_path=""
version=""

trap ctrl_c INT

clean() {
    exit_code=$1

    # Clean the files
    rm -rf ${dockerfile_path}/{*.sh,*.tar.gz,wazuh-*,*.tar.gz,*.zip}

    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

build_deb() {
    container_name="$1"
    dockerfile_path="$2"

    if [ "${repository}" ];then
        url="${repository}"
    fi

    # Copy the necessary files
    cp ${current_path}/builder.sh ${dockerfile_path}

    if [ "${build_base}" == "yes" ];then
        # Base generation
        if [ "${url}" ];then
            base_cmd+="--app-url ${url} "
        fi
        if [ "${dashboard_url}" ];then
            base_cmd+="--dashboard-url ${dashboard_url} "
        fi
        if [ "${dashboard_path}" ];then
            base_cmd+="--dashboard-path ${dashboard_path} "
        fi
        if [ "${security_url}" ];then
            base_cmd+="--security-url ${security_url} "
        fi
        if [ "${security_path}" ];then
            base_cmd+="--security-path ${security_path} "
        fi
        if [ "${version}" ];then
            base_cmd+="--version ${version} "
        fi
        echo ${base_cmd}
        ../base/generate_base.sh -s ${outdir} -r ${revision} ${base_cmd}
    fi

    # Build the Docker image
    if [[ ${build_docker} == "yes" ]]; then
        docker build -t ${container_name} ${dockerfile_path} || return 1
    fi

    # Build the Debian package with a Docker container
    volumes="-v ${outdir}/:/tmp:Z"
    docker run -t --rm ${volumes} \
        -v ${current_path}/../..:/root:Z \
        ${container_name} ${architecture}  \
        ${revision} ${url} ${version} || return 1

    echo "Package $(ls -Art ${outdir} | tail -n 1) added to ${outdir}."

    return 0
}

build() {
    build_name=""
    file_path=""
    if [ "${architecture}" = "x86_64" ] || [ "${architecture}" = "amd64" ]; then
        architecture="amd64"
        build_name="${deb_amd64_builder}"
        file_path="${deb_builder_dockerfile}/${architecture}"
    else
        echo "Invalid architecture. Choose: amd64 (x86_64 is accepted too)"
        return 1
    fi
    build_deb ${build_name} ${file_path} || return 1

    return 0
}

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "    --app-url <url>            [Optional] Set the repository from where the Wazuh plugin should be downloaded. By default, will be used pre-release."
    echo "    --dashboard-url <url>      Set the repository from where the .tar.gz file containing Wazuh Dashboard should be downloaded. "
    echo "    --dashboard-path <path>    Set the location of the .tar.gz file containing the Wazuh Dashboard."
    echo "    --security-url <url>       Set the repository from where the .zip file containing the Security plugin should be downloaded."
    echo "    --security-path <path>     Set the location of the .zip file containing the security plugin."
    echo "    -v, --version <rev>        Wazuh version"
    echo "    -a, --architecture <arch>  [Optional] Target architecture of the package [amd64]."
    echo "    -b, --build-base <yes/no>  [Optional] Build a new base or use a existing one. By default, yes."
    echo "    -r, --revision <rev>       [Optional] Package revision. By default: 1."
    echo "    -s, --store <path>         [Optional] Set the destination path of package. By default, an output folder will be created."
    echo "    --dont-build-docker        [Optional] Locally built docker image will be used instead of generating a new one."
    echo "    -h, --help                 Show this help."
    echo
    echo "    At least one of the app and one of the security options must be provided"
    exit $1
}


main() {
    while [ -n "${1}" ]
    do
        case "${1}" in
        "-h"|"--help")
            help 0
            ;;
        "-a"|"--architecture")
            if [ -n "${2}" ]; then
                architecture="${2}"
                shift 2
            else
                help 1
            fi
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
            "-v"|"--version")
            if [ -n "${2}" ]; then
                version="${2}"
                shift 2
            else
                help 1
            fi
            ;;
        "-b"|"--build-base")
            if [ -n "${2}" ]; then
                build_base="${2}"
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
        "--dont-build-docker")
            build_docker="no"
            shift 1
            ;;
        "-s"|"--store")
            if [ -n "${2}" ]; then
                outdir="${2}"
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
