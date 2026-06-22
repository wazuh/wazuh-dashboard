#!/bin/bash

# Run a DEB package test body inside a privileged, systemd-enabled container.
# The CI runner has no systemd as PID 1, so wazuh-dashboard's maintainer scripts
# (which call systemctl) can't run on the host. This boots a throwaway systemd
# container, waits for systemd, runs the body via `docker exec`, and tears it down.
#
# Usage: run_in_systemd_container.sh <workspace> <script-body>
#   workspace    Host workspace root; dev-tools/test-packages is bind-mounted to /test-packages.
#   script-body  Bash snippet executed inside the container.

set -e

WORKSPACE="$1"
SCRIPT_BODY="$2"

if [ -z "$WORKSPACE" ] || [ -z "$SCRIPT_BODY" ]; then
  echo "Usage: $0 <workspace> <script-body>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Built locally on first call and reused via the layer cache.
# Override SYSTEMD_IMAGE with a prebuilt image to skip the build.
SYSTEMD_IMAGE="${SYSTEMD_IMAGE:-wazuh-dashboard-systemd-test:jammy}"

if ! docker image inspect "$SYSTEMD_IMAGE" >/dev/null 2>&1; then
  echo "Building systemd test image ${SYSTEMD_IMAGE}..."
  docker build -t "$SYSTEMD_IMAGE" \
    -f "${SCRIPT_DIR}/builder/systemd-test.Dockerfile" \
    "${SCRIPT_DIR}/builder"
fi

cid=$(docker run -d --rm \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "${WORKSPACE}/dev-tools/test-packages:/test-packages" \
  "$SYSTEMD_IMAGE" /sbin/init)

trap 'docker stop "$cid" >/dev/null 2>&1 || true' EXIT

# Wait for systemd to finish booting before exercising any service units.
ready=false
for _ in $(seq 1 30); do
  state=$(docker exec "$cid" systemctl is-system-running 2>/dev/null || true)
  case "$state" in
    running | degraded)
      ready=true
      break
      ;;
  esac
  sleep 1
done

if [ "$ready" != true ]; then
  echo "ERROR: systemd did not become ready in the container (last state: ${state:-unknown})"
  docker logs "$cid" || true
  exit 1
fi

docker exec "$cid" bash -c "$SCRIPT_BODY"
