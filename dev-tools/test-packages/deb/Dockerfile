FROM ubuntu:jammy
ARG PACKAGE
ARG BLOCK_4X_INSTALL
ARG BLOCK_UNKNOWN_INSTALL
ARG ALLOW_SAME_MAJOR_REINSTALL
RUN mkdir -p /tmp
RUN apt-get update --fix-missing
RUN apt-get install -y curl libcap2-bin

# If BLOCK_4X_INSTALL is set, simulate a 4.x installation via the plugin's package.json
# (the preinst guard falls through VERSION.json -> VERSION -> plugin package.json)
RUN if [ -n "$BLOCK_4X_INSTALL" ]; then \
      mkdir -p /usr/share/wazuh-dashboard/plugins/wazuh && \
      printf '{"name":"wazuh","version":"4.14.5"}\n' > /usr/share/wazuh-dashboard/plugins/wazuh/package.json; \
    fi

COPY ${PACKAGE} /tmp/wazuh.deb

# BLOCK_UNKNOWN_INSTALL: install once (fresh, $1=install — allowed), then corrupt
# version files so the version cannot be determined, then attempt a reinstall
# ($1=upgrade) which must be blocked by the preinst guard.
#
# ALLOW_SAME_MAJOR_REINSTALL: install twice — must succeed (5.x over 5.x).
#
# Default: normal install (also handles BLOCK_4X_INSTALL via the files pre-created above).
RUN if [ -n "$BLOCK_UNKNOWN_INSTALL" ]; then \
      dpkg -i /tmp/wazuh.deb && \
      rm -f /usr/share/wazuh-dashboard/VERSION.json && \
      rm -f /usr/share/wazuh-dashboard/VERSION && \
      rm -f /usr/share/wazuh-dashboard/plugins/wazuh/package.json && \
      dpkg -i /tmp/wazuh.deb; \
    elif [ -n "$ALLOW_SAME_MAJOR_REINSTALL" ]; then \
      dpkg -i /tmp/wazuh.deb && \
      dpkg -i /tmp/wazuh.deb; \
    else \
      dpkg -i /tmp/wazuh.deb; \
    fi
