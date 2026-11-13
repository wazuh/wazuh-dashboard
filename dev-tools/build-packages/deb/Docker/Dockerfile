FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

# Installing necessary packages
RUN apt-get update && apt-get install -y --allow-change-held-packages apt-utils && \
    apt-get install -y --allow-change-held-packages \
    curl sudo wget expect gnupg build-essential \
    devscripts equivs selinux-basics procps gawk jq

# The builder script and its inputs are mounted at run time by
# build-packages.sh, so this Dockerfile is the only input of the image.
ENTRYPOINT ["/bin/bash", "/usr/local/bin/builder"]
