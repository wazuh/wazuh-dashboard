FROM centos:8
RUN mkdir -p /tmp
ARG PACKAGE
ARG BLOCK_4X_INSTALL
ARG BLOCK_UNKNOWN_INSTALL
ARG ALLOW_SAME_MAJOR_REINSTALL
RUN cd /etc/yum.repos.d/
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
RUN sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
RUN yum update -y

# If BLOCK_4X_INSTALL is set, simulate a 4.x installation via the plugin's package.json
# (the %pre guard falls through VERSION.json -> VERSION -> plugin package.json)
RUN if [ -n "$BLOCK_4X_INSTALL" ]; then \
      mkdir -p /usr/share/wazuh-dashboard/plugins/wazuh && \
      printf '{"name":"wazuh","version":"4.14.5"}\n' > /usr/share/wazuh-dashboard/plugins/wazuh/package.json; \
    fi

COPY ${PACKAGE} /tmp/wazuh.rpm

# BLOCK_UNKNOWN_INSTALL: install once (fresh, $1=1 — allowed), then corrupt
# version files so the version cannot be determined, then attempt an upgrade
# ($1=2) which must be blocked by the %pre guard.
#
# ALLOW_SAME_MAJOR_REINSTALL: install then upgrade — must succeed (5.x over 5.x).
#
# Default: normal install (also handles BLOCK_4X_INSTALL via the files pre-created above).
RUN if [ -n "$BLOCK_UNKNOWN_INSTALL" ]; then \
      rpm -ivh /tmp/wazuh.rpm --nodeps && \
      rm -f /usr/share/wazuh-dashboard/VERSION.json && \
      rm -f /usr/share/wazuh-dashboard/VERSION && \
      rm -f /usr/share/wazuh-dashboard/plugins/wazuh/package.json && \
      rpm -Uvh /tmp/wazuh.rpm --nodeps --force; \
    elif [ -n "$ALLOW_SAME_MAJOR_REINSTALL" ]; then \
      rpm -ivh /tmp/wazuh.rpm --nodeps && \
      rpm -Uvh /tmp/wazuh.rpm --nodeps --force; \
    else \
      yum install /tmp/wazuh.rpm -y; \
    fi
