#!/bin/bash

# Wazuh package builder
# Copyright (C) 2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

set -e

# Script parameters to build the package
target="wazuh-dashboard"
architecture=$1
revision=$2
version=$3
directory_base="/usr/share/wazuh-dashboard"

# Build directories
build_dir=/build
rpm_build_dir=${build_dir}/rpmbuild
pkg_name=${target}-${version}
pkg_path="${rpm_build_dir}/RPMS/${architecture}"
file_name="${target}-${version}-${revision}"
rpm_file="${file_name}.${architecture}.rpm"

mkdir -p ${rpm_build_dir}/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Prepare the sources directory to build the source tar.gz
mkdir ${build_dir}/${pkg_name}

# Including spec file
cp /root/build-packages/rpm/${target}.spec ${rpm_build_dir}/SPECS/${pkg_name}.spec

# Generating source tar.gz
cd ${build_dir} && tar czf "${rpm_build_dir}/SOURCES/${pkg_name}.tar.gz" "${pkg_name}"

# Building RPM
/usr/bin/rpmbuild -v \
    --define "_topdir ${rpm_build_dir}" \
    --define "_version ${version}" \
    --define "_release ${revision}" \
    --define "_localstatedir ${directory_base}" \
    --target ${architecture} \
    -ba ${rpm_build_dir}/SPECS/${pkg_name}.spec

cd ${pkg_path} && sha512sum ${rpm_file} >/tmp/${rpm_file}.sha512

find ${pkg_path}/ -maxdepth 3 -type f -name "${file_name}*" -exec mv {} /tmp/ \;
