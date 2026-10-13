#!/bin/bash
# Checks that wazuh-dashboard listens on its port as a non-root process whose only capability,
# CAP_NET_BIND_SERVICE, comes from its unit. `active (running)` alone holds before node binds.
#
# Usage: check-service-bind.sh [timeout-seconds]

set -uo pipefail

NAME=wazuh-dashboard
TIMEOUT="${1:-180}"
CAP_NET_BIND_SERVICE=0000000000000400

port=$(awk -F: '/^server\.port:/ { gsub(/[ \t'"'"'"]/, "", $2); print $2 }' \
  "/etc/${NAME}/opensearch_dashboards.yml" 2>/dev/null)
port="${port:-443}"
port_hex=$(printf '%04X' "${port}")

# A socket in LISTEN state (0A) on the port, from the kernel tables (no iproute2 needed).
listening() {
  grep -qE "^ *[0-9]+: [0-9A-F]+:${port_hex} [0-9A-F]+:[0-9A-F]+ 0A " /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

deadline=$((SECONDS + TIMEOUT))
until listening; do
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    echo "Service not listening on port ${port} after ${TIMEOUT}s"
    journalctl -u "${NAME}" --no-pager | tail -50
    exit 1
  fi
  sleep 2
done
echo "Service listening on port ${port}"

pid=$(systemctl show -p MainPID --value "${NAME}")
status_file="/proc/${pid}/status"
if [ -n "${pid}" ] && [ "${pid}" != 0 ] &&
  awk -v want="${CAP_NET_BIND_SERVICE}" '/^Uid:/ { uid = $2 } /^Cap(Eff|Amb|Bnd):/ { cap[$1] = $2 }
    END { exit !(uid != 0 && cap["CapEff:"] == want && cap["CapAmb:"] == want && cap["CapBnd:"] == want) }' \
    "${status_file}"; then
  echo "Service runs as non-root with only CAP_NET_BIND_SERVICE, from its unit"
else
  echo "Service user or capabilities are wrong"
  grep -E '^(Uid|Cap(Eff|Amb|Bnd)):' "${status_file}" 2>/dev/null || echo "No main process"
  exit 1
fi
