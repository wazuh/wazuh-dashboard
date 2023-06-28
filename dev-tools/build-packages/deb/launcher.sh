#!/bin/bash

# Wazuh package generator
# Copyright (C) 2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

current_path="$( cd $(dirname $0) ; pwd -P )"
outdir="${current_path}/output"
revision="1"
architecture="amd64"
build_docker="yes"
deb_amd64_builder="deb_dashboard_builder_amd64"
deb_builder_dockerfile="${current_path}/docker"
build_base="yes"
package=""
version=""

trap ctrl_c INT

clean() {
    exit_code=$1
    echo
    echo "Cleaning temporary files..."
    echo
    # Clean the files
    rm -rf ${dockerfile_path}/{*.sh,*.tar.gz,wazuh-*,*.tar.gz,*.zip} wazuh-dashboard.tar.gz wazuh-dashboard-base

    if [ $exit_code != 0 ]; then
        rm -rf $output/*
    fi

    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

build_deb() {
  container_name="$1"
  dockerfile_path="$2"

  # Validate and download files to build the package
  valid_url='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'

  echo
  echo "Downloading files..."
  echo
  if [[ $package =~ $valid_url ]];then
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
  directory_name=$(tar tf wazuh-dashboard.tar.gz | head -1 | sed 's#/.*##'  | sort -u)
  tar -zxf wazuh-dashboard.tar.gz
  rm wazuh-dashboard.tar.gz
  mv $directory_name wazuh-dashboard-base
  cp ../config/* wazuh-dashboard-base
  echo ${version} > wazuh-dashboard-base/VERSION
  tar -czf ./wazuh-dashboard.tar.gz wazuh-dashboard-base


  # Copy the necessary files
  cp ${current_path}/builder.sh ${dockerfile_path}

  # Build the Docker image
  if [[ ${build_docker} == "yes" ]]; then
    docker build -t ${container_name} ${dockerfile_path} || return 1
  fi

  # Build the Debian package with a Docker container
  volumes="-v ${outdir}/:/tmp:Z -v ${current_path}/wazuh-dashboard.tar.gz:/opt/wazuh-dashboard.tar.gz"
  docker run -t --rm ${volumes} \
    -v ${current_path}/../..:/root:Z \
    ${container_name} ${architecture}  \
    ${revision} ${version} || return 1

  echo "Package $(ls -Art ${outdir} | tail -n 1) added to ${outdir}."

  echo
  echo DONE!
  echo

  return 0
}

build() {
    build_name="${deb_amd64_builder}"
    file_path="${deb_builder_dockerfile}/${architecture}"
    build_deb ${build_name} ${file_path} || return 1
    return 0
}

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "    -v, --version <rev>        Wazuh version"
    echo "    -p, --package <path>       Set the location of the .tar.gz file containing the Wazuh Dashboard package."
    echo "    -r, --revision <rev>       [Optional] Package revision. By default: 1."
    echo "    -s, --output <path>        [Optional] Set the destination path of package. By default, an output folder will be created."
    echo "    --dont-build-docker        [Optional] Locally built docker image will be used instead of generating a new one."
    echo "    -h, --help                 Show this help."
    echo
    exit $1
}


main() {
    while [ -n "${1}" ]
    do
        case "${1}" in
        "-h"|"--help")
            help 0
            ;;
        "-p"|"--package")
            if [ -n "${2}" ]; then
                package="${2}"
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
        "--dont-build-docker")
            build_docker="no"
            shift 1
            ;;
        "-s"|"--output")
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

    if [ -z "$package" ] | [ -z "$version" ] ; then
      help 1
    fi

    build || clean 1

    clean 0
}

main "$@"
