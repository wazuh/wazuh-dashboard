#!/bin/bash

# Prints the reference of a dashboard package builder image:
#   ghcr.io/wazuh/pkg_dashboard_<image>_builder_<arch>:<version>-<hash>
# <version> is `.version` in the repository VERSION.json and <hash> the first
# 12 hex chars of the sha256 of the image's Dockerfile, so a Dockerfile change
# always gets a new tag and published tags never need to be overwritten.
#
# Usage:
#   bash builder-image.sh <base|rpm|deb> <amd64|arm64>
# or source it and call:
#   builder_image_ref <base|rpm|deb> <amd64|arm64>

builder_image_build_packages_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

builder_image_ref() {
  local image="$1"
  local arch="$2"
  local dockerfile
  local version
  local hash

  case "${image}" in
  base | rpm | deb) ;;
  *)
    echo "Unknown builder image '${image}'. Expected base, rpm or deb." >&2
    return 1
    ;;
  esac

  case "${arch}" in
  amd64 | arm64) ;;
  *)
    echo "Unknown builder architecture '${arch}'. Expected amd64 or arm64." >&2
    return 1
    ;;
  esac

  dockerfile="${builder_image_build_packages_dir}/${image}/Docker/Dockerfile"
  version="$(jq -r '.version' "${builder_image_build_packages_dir}/../../VERSION.json")" || return 1
  if [ -z "${version}" ] || [ "${version}" = "null" ]; then
    echo "Could not read the version from VERSION.json." >&2
    return 1
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "${dockerfile}")" || return 1
  else
    hash="$(shasum -a 256 "${dockerfile}")" || return 1
  fi

  echo "ghcr.io/wazuh/pkg_dashboard_${image}_builder_${arch}:${version}-${hash:0:12}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ $# -ne 2 ]; then
    echo "Usage: $0 <base|rpm|deb> <amd64|arm64>" >&2
    exit 1
  fi
  builder_image_ref "$1" "$2"
fi
