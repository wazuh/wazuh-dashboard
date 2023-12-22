#!/bin/bash

app=""
base=""
revision="1"
security=""
version=""
all_platforms="no"
deb="no"
rpm="no"
tar="no"
output="$( cd $(dirname $0) ; pwd -P )/output"

current_path="$( cd $(dirname $0) ; pwd -P )"

build_tar() {
  echo "Building tar package..."
  cd ./base
  bash ./generate_base.sh -a $app -b $base -s $security -v $version -r $revision

  name_package_tar=$(ls ./output)

  echo "Moving tar package to $output"
  mv $current_path/base/output/$name_package_tar $output/$name_package_tar
  cd ../
}

build_deb() {
  echo "Building deb package..."
  name_package_tar=$(find $output -name "*.tar.gz")
  cd ./deb
  bash ./launcher.sh -v $version -r $revision -p file://$name_package_tar
  name_package_tar=$(ls ./output)
  echo "Moving deb package to $output/deb"
  mv $current_path/deb/output $output/deb
  cd ../
}

build_rpm() {
  echo "Building rpm package..."
  name_package_tar=$(find $output -name "*.tar.gz")
  cd ./rpm
  bash ./launcher.sh -v $version -r $revision -p file://$name_package_tar
  echo "Moving rpm package to $output/rpm"
  mv $current_path/rpm/output $output/rpm
  cd ../
}


build() {
  name_package_tar="wazuh-dashboard-$version-$revision-linux-x64.tar.gz"

  if [ ! -d "$output" ]; then
    mkdir $output
  fi

  if [ "$all_platforms" == "yes" ]; then
    deb="yes"
    rpm="yes"
    tar="yes"
  fi

  build_tar
  cd $current_path

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
    rm -r $(find $output -name "*.tar.gz")
  fi
}

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo "    -a, --app <url/path>          Set the location of the .zip file containing the Wazuh plugin."
    echo "    -b, --base <url/path>         Set the location of the .tar.gz file containing the base wazuh-dashboard build."
    echo "    -s, --security <url/path>     Set the location of the .zip file containing the wazuh-security-dashboards-plugin."
    echo "    -v, --version <version>       Set the version of this build."
    echo "        --all-platforms           Build for all platforms."
    echo "        --deb                     Build for deb."
    echo "        --rpm                     Build for rpm."
    echo "        --tar                     Build for tar."
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

    build || exit 1

    exit 0
}

main "$@"
