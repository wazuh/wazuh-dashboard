FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash \
       ca-certificates \
       coreutils \
       jq \
       bats \
       git \
       grep \
       sed \
       gawk \
       findutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
