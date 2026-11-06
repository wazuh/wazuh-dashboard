FROM rockylinux:8.5

# Install all the necessary tools to build the packages
RUN yum clean all && yum update -y
RUN yum install -y openssh-clients sudo gnupg \
    yum-utils epel-release redhat-rpm-config rpm-devel \
    zlib zlib-devel rpm-build autoconf automake \
    glibc-devel libtool perl jq

#RUN yum install -y --nobest https://repo.ius.io/ius-release-el7.rpm

RUN yum update -y && yum install -y python3

RUN ln -fs /usr/bin/python3.6 /usr/bin/python

# The builder script and its inputs are mounted at run time by
# build-packages.sh, so this Dockerfile is the only input of the image.
ENTRYPOINT ["/bin/bash", "/usr/local/bin/builder"]
