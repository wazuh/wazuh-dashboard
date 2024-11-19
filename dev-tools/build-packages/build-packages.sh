#!/bin/bash
set -e

app=""
base=""
revision="1"
security=""
version=""
reportPlugin=""
all_platforms="no"
deb="no"
rpm="no"
tar="no"
architecture="x64"
production="no"
commit_sha=$(git rev-parse --short HEAD)
current_path="$( cd $(dirname $0) ; pwd -P )"
output_dir="${current_path}/output"
tmp_dir="${current_path}/tmp"
config_dir="${current_path}/../../config"
package_config_dir="${current_path}/config"
verbose="info"

trap clean INT
trap clean EXIT

log() {
    if [ "$verbose" = "info" ] || [ "$verbose" = "debug" ]; then
        echo "$@"
    fi
}

clean() {
    exit_code=$?
    echo
    echo "Cleaning temporary files..."
    echo
    # Clean the files
    rm -rf ${tmp_dir}
    rm -f ${current_path}/base/Docker/base-builder.sh
    rm -f ${current_path}/base/Docker/plugins
    rm -f ${current_path}/rpm/Docker/rpm-builder.sh
    rm -f ${current_path}/rpm/Docker/wazuh-dashboard.spec
    rm -f ${current_path}/deb/Docker/deb-builder.sh
    rm -rf ${current_path}/deb/Docker/debian
    trap '' EXIT
    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

get_packages(){
  packages_list=(app base security reportPlugin)
  packages_names=("Wazuh plugins" "Wazuh Dashboard" "Security plugin" "Report plugin")
  valid_url='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
  mkdir -p ${tmp_dir}
  cd ${tmp_dir}
  mkdir -p packages
  for i in "${!packages_list[@]}"; do
    package_var="${packages_list[$i]}"
    package_name="${packages_names[$i]}"
    package_url="${!package_var}"

    log
    log "Downloading ${package_name}"

    if [[ $package_url =~ $valid_url ]]; then
      if ! curl --output "packages/${package_var}.zip" --silent --fail "${package_url}"; then
        echo "The given URL or Path to the ${package_name} is not working: ${package_url}"
        clean 1
      fi
    else
      echo "The given URL or Path to the ${package_name} is not valid: ${package_url}"
      clean 1
    fi
    log "Done!"
    log
  done
  cd ..
}

source ../utils/retry-operation.sh

build_tar() {
  log
  log "Building base package..."
  log
  mkdir -p ${output_dir}
  cp -r ${config_dir} ${tmp_dir}
  cd ./base
  dockerfile_path="${current_path}/base/Docker"
  container_name="dashboard-base-builder"
  cp ./base-builder.sh ${dockerfile_path}
  cp ./plugins ${dockerfile_path}
  retry_operation "build base package" 5 15 \
        "docker build -t ${container_name} ${dockerfile_path} && \
         docker run -t --rm \
         -v ${tmp_dir}/:/tmp:Z \
         -v ${output_dir}/:/output:Z \
         ${container_name} ${version} ${revision} ${architecture} ${verbose}" || exit 1
  cd ..
}

build_rpm() {
  log "Building rpm package..."
  cd ./rpm
  dockerfile_path="${current_path}/rpm/Docker"
  container_name="dashboard-rpm-builder"
  cp -r ${package_config_dir} ${tmp_dir}
  cp ./rpm-builder.sh ${dockerfile_path}
  cp ./wazuh-dashboard.spec ${dockerfile_path}
  retry_operation "build rpm package" 5 15 \
      "docker build -t ${container_name} ${dockerfile_path} && \
        docker run -t --rm \
        -v ${tmp_dir}/:/tmp:Z \
        -v ${output_dir}/:/output:Z \
        ${container_name} ${version} ${revision} ${architecture} \
        ${commit_sha} ${production} ${verbose}" || exit 1
  cd ../
}


build_deb() {
  log "Building deb package..."
  cd ./deb
  dockerfile_path="${current_path}/deb/Docker"
  container_name="dashboard-deb-builder"
  cp -r ${package_config_dir} ${tmp_dir}
  cp ./deb-builder.sh ${dockerfile_path}
  cp -r ./debian ${dockerfile_path}
  docker build -t ${container_name} ${dockerfile_path} || return 1
  retry_operation "build deb package" 5 15 \
        "docker build -t ${container_name} ${dockerfile_path} && \
         docker run -t --rm \
         -v ${tmp_dir}/:/tmp:Z \
         -v ${output_dir}/:/output:Z \
         ${container_name} ${version} ${revision} ${architecture} \
         ${commit_sha} ${production} ${verbose}" || exit 1
  cd ..
}




build(){
  log "Building package..."
  if [ "$all_platforms" == "yes" ]; then
    deb="yes"
    rpm="yes"
    tar="yes"
  fi
  get_packages
  build_tar

  if [ $deb == "yes" ]; then
    echo "Building deb package..."
    build_deb
  fi

  if [ $rpm == "yes" ]; then
    echo "Building rpm package..."
    build_rpm
  fi

  if [ "$tar" == "no" ]; then
    echo "Removing tar package..."
    rm -r $(find $output_dir -name "*.tar.gz")
  fi
}

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo "    -a, --app <url/path>          Set the location of the .zip file containing the Wazuh plugin."
    echo "    -b, --base <url/path>         Set the location of the .tar.gz file containing the base wazuh-dashboard build."
    echo "    -s, --security <url/path>     Set the location of the .zip file containing the wazuh-security-dashboards-plugin."
    echo "    -rp, --reportPlugin <url/path> Set the location of the .zip file containing the wazuh-reporting-plugin."
    echo "    -v, --version <version>       Set the version of this build."
    echo "        --all-platforms           Build for all platforms."
    echo "        --deb                     Build for deb."
    echo "        --rpm                     Build for rpm."
    echo "        --tar                     Build for tar."
    echo "    --production                  [Optional] The naming of the package will be ready for production."
    echo "    --arm                         [Optional] Build for arm64 instead of x64."
    echo "    --debug                       [Optional] Debug mode."
    echo "    --silent                      [Optional] Silent mode. Will not work if --debug is set."
    echo "    -r, --revision <revision>     [Optional] Set the revision of this build. By default, it is set to 1."
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
        "-rp" | "--reportPlugin")
            if [ -n "${2}" ]; then
                reportPlugin="${2}"
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
        "--production")
            production="yes"
            shift 1
            ;;
        "--all-platforms")
            all_platforms="yes"
            shift 1
            ;;
        "--deb")
            deb="yes"
            shift 1
            ;;
        "--rpm")
            rpm="yes"
            shift 1
            ;;
        "--tar")
            tar="yes"
            shift 1
            ;;
        "--arm")
            architecture="arm64"
            shift 1
            ;;
        "--silent")
            verbose="silent"
            shift 1
            ;;
        "--debug")
            verbose="debug"
            shift 1
            ;;

        "-o" | "--output")
            if [ -n "${2}" ]; then
                output="${2}"
                shift 2
            fi
            ;;
        *)
            echo "help"

            help 1
            ;;
        esac
    done

    if [ -z "$app" ] | [ -z "$base" ] | [ -z "$security" ] | [ -z "$version" ]; then
        echo "You must specify the app, base, security and version."
        help 1
    fi

    if [ "$all_platforms" == "no" ] && [ "$deb" == "no" ] && [ "$rpm" == "no" ] && [ "$tar" == "no" ]; then
        echo "You must specify at least one package to build."
        help 1
    fi

    if [ "$verbose" = "debug" ]; then
      set -x
    fi

    build || exit 1

    exit 0
}

main "$@"
