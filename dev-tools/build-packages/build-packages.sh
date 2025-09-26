#!/bin/bash
set -e

current_path="$( cd $(dirname $0) ; pwd -P )"
root_dir="${current_path}/../.."
app=""
base=""
revision="1"
security=""
ml=""
version="$(jq -r '.version' ${root_dir}/VERSION.json)"
all_platforms="no"
deb="no"
rpm="no"
tar="no"
architecture="x64"
production="no"
retry_max_attempts=3
retry_delay_seconds=15
commit_sha=$(git rev-parse --short HEAD)
output_dir="${current_path}/output"
tmp_dir="${current_path}/tmp"
config_dir="${root_dir}/config"
package_config_dir="${current_path}/config"
verbose="info"

trap clean INT
trap clean EXIT

log() {
    if [ "$verbose" = "info" ] || [ "$verbose" = "debug" ]; then
        echo "$@"
    fi
}

run_with_retry() {
    local attempt=1
    local exit_code=0

    while [ "${attempt}" -le "${retry_max_attempts}" ]; do
        "$@" # Run the command
        exit_code=$?
        if [ ${exit_code} -eq 0 ]; then
            return 0
        fi

        if [ "${attempt}" -ge "${retry_max_attempts}" ]; then
            echo "Command failed after ${retry_max_attempts} attempts (exit code ${exit_code}): $*" >&2
            return ${exit_code}
        fi

        local next_attempt=$((attempt + 1))
        if [ "$verbose" != "silent" ]; then
            echo "Command failed (attempt ${attempt}/${retry_max_attempts}, exit ${exit_code}). Retrying in ${retry_delay_seconds}s (attempt ${next_attempt}/${retry_max_attempts})." >&2
        fi

        if [ "${retry_delay_seconds}" -gt 0 ]; then
            sleep "${retry_delay_seconds}"
        fi

        attempt=$((attempt + 1))
    done
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
  packages_list=(app base security ml)
  packages_names=("Wazuh plugins" "Wazuh Dashboard" "Security plugin" "ML Commons plugin")
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
      if ! run_with_retry curl --output "packages/${package_var}.zip" --silent --show-error --fail "${package_url}"; then
        echo "Failed to download ${package_name} after ${retry_max_attempts} attempts: ${package_url}"
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
  cp ${root_dir}/VERSION.json ${dockerfile_path}
  run_with_retry docker build -t "${container_name}" "${dockerfile_path}" || return 1
  run_with_retry docker run -t --rm -v "${tmp_dir}/:/tmp:Z" -v "${output_dir}/:/output:Z" \
    "${container_name}" "${version}" "${revision}" "${architecture}" "${verbose}" || return 1
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
  run_with_retry docker build -t "${container_name}" "${dockerfile_path}" || return 1
  run_with_retry docker run -t --rm -v "${tmp_dir}/:/tmp:Z" -v "${output_dir}/:/output:Z" \
    "${container_name}" "${version}" "${revision}" "${architecture}" \
    "${commit_sha}" "${production}" "${verbose}" || return 1
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
  run_with_retry docker build -t "${container_name}" "${dockerfile_path}" || return 1
  run_with_retry docker run -t --rm -v "${tmp_dir}/:/tmp:Z" -v "${output_dir}/:/output:Z" \
    "${container_name}" "${version}" "${revision}" "${architecture}" \
    "${commit_sha}" "${production}" "${verbose}" || return 1
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
    echo "    -c, --commit-sha <sha>        Set the commit sha of this build."
    echo "    -a, --app <url/path>          Set the location of the .zip file containing the Wazuh plugin."
    echo "    -b, --base <url/path>         Set the location of the .tar.gz file containing the base wazuh-dashboard build."
    echo "    -s, --security <url/path>     Set the location of the .zip file containing the wazuh-security-dashboards-plugin."
    echo "    -m, --ml <url/path>           Set the location of the .zip file containing the wazuh-dashboard-ml-commons plugin."
    echo "        --all-platforms           Build for all platforms."
    echo "        --deb                     Build for deb."
    echo "        --rpm                     Build for rpm."
    echo "        --tar                     Build for tar."
    echo "        --production              [Optional] The naming of the package will be ready for production."
    echo "        --arm                     [Optional] Build for arm64 instead of x64."
    echo "        --debug                   [Optional] Debug mode."
    echo "        --retry-attempts <n>      [Optional] Retry transient steps up to n times. Defaults to 3."
    echo "        --retry-delay <seconds>   [Optional] Seconds to wait between retries. Defaults to 15."
    echo "        --silent                  [Optional] Silent mode. Will not work if --debug is set."
    echo "    -r, --revision <revision>     [Optional] Set the revision of this build. By default, it is set to 1."
    echo "    -h, --help                    Show this help."
    echo
    exit $1
}

# -----------------------------------------------------------------------------

main() {
    echo $0 "$@"

    while [ -n "${1}" ]; do
        case "${1}" in
        "-c" | "--commit-sha")
            if [ -n "${2}" ]; then
                commit_sha="${2}"
                shift 2
            else
                help 0
            fi
            ;;
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
        "-m" | "--ml")
            if [ -n "${2}" ]; then
                ml="${2}"
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
        "--retry-attempts")
            if [ -n "${2}" ] && [[ "${2}" =~ ^[0-9]+$ ]] && [ "${2}" -gt 0 ]; then
                retry_max_attempts="${2}"
                shift 2
            else
                echo "Invalid value for --retry-attempts. It must be a positive integer."
                help 1
            fi
            ;;
        "--retry-delay")
            if [ -n "${2}" ] && [[ "${2}" =~ ^[0-9]+$ ]]; then
                retry_delay_seconds="${2}"
                shift 2
            else
                echo "Invalid value for --retry-delay. It must be a non-negative integer."
                help 1
            fi
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
            echo "Unknown option: ${1}"
            help 1
            ;;
        esac
    done

    if [ -z "$app" ] || [ -z "$base" ] || [ -z "$security" ] || [ -z "$ml" ]; then
        echo "You must specify the app, base, security, and ML Commons plugin."
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
