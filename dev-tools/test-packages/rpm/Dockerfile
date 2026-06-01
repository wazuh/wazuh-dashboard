FROM centos:8
RUN mkdir -p /tmp
ARG PACKAGE
ARG SIMULATE_4X
ARG REINSTALL_5X
RUN cd /etc/yum.repos.d/
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
RUN sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
RUN yum update -y

# If SIMULATE_4X is set, create a VERSION.json on disk to simulate
# an existing pre-5.x installation (the %pre guard checks this file)
RUN if [ -n "$SIMULATE_4X" ]; then \
      mkdir -p /usr/share/wazuh-dashboard && \
      printf '{"version": "4.14.5"}' > /usr/share/wazuh-dashboard/VERSION.json; \
    fi

COPY ${PACKAGE} /tmp/wazuh.rpm

# If REINSTALL_5X: install the 5.x package once, then force a reinstall
# to exercise the %pre guard again (must allow same-major-version reinstall)
RUN if [ -n "$REINSTALL_5X" ]; then \
      rpm -ivh /tmp/wazuh.rpm --nodeps && \
      rpm -Uvh /tmp/wazuh.rpm --nodeps; \
    else \
      yum install /tmp/wazuh.rpm -y; \
    fi
