FROM ubuntu:jammy
ARG PACKAGE
ARG SIMULATE_4X
ARG REINSTALL_5X
RUN mkdir -p /tmp
RUN apt-get update --fix-missing
RUN apt-get install -y curl libcap2-bin

# If SIMULATE_4X is set, create a VERSION.json on disk to simulate
# an existing pre-5.x installation (the preinst guard checks this file)
RUN if [ -n "$SIMULATE_4X" ]; then \
      mkdir -p /usr/share/wazuh-dashboard && \
      printf '{"version": "4.14.5"}' > /usr/share/wazuh-dashboard/VERSION.json; \
    fi

COPY ${PACKAGE} /tmp/wazuh.deb

# If REINSTALL_5X: install the 5.x package once, then force a reinstall
# to exercise the preinst guard again (must allow same-major-version reinstall)
RUN if [ -n "$REINSTALL_5X" ]; then \
      dpkg -i /tmp/wazuh.deb && \
      dpkg -i /tmp/wazuh.deb; \
    else \
      dpkg -i /tmp/wazuh.deb; \
    fi
