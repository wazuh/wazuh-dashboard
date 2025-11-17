#!/bin/bash

# Utility helpers to temporarily disable the network interface inside
# the package-building containers. This allows us to simulate transient
# network outages and verify that the retry logic is behaving as expected.

NETWORK_DISRUPTION_PID=""
NETWORK_DISRUPTION_INTERFACE=""

_detect_primary_interface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

start_network_disconnection_timer() {
  local delay="${SIMULATE_NETWORK_DISCONNECTION_AFTER:-60}"
  local duration="${SIMULATE_NETWORK_DISCONNECTION_DURATION:-30}"
  local iface="${SIMULATE_NETWORK_INTERFACE:-$(_detect_primary_interface)}"

  if [ -z "${iface}" ]; then
    echo "[network-simulator] Unable to determine the default network interface" >&2
    return 0
  fi

  if [ -n "${NETWORK_DISRUPTION_PID}" ]; then
    return 0
  fi

  (
    sleep "${delay}" || exit 0
    echo "[network-simulator] Simulating network outage on ${iface} for ${duration}s" >&2
    if ! ip link set "${iface}" down 2>/dev/null; then
      echo "[network-simulator] Failed to bring interface ${iface} down" >&2
      exit 0
    fi

    sleep "${duration}" || true

    ip link set "${iface}" up 2>/dev/null || true
    echo "[network-simulator] Network restored on ${iface}" >&2
  ) &

  NETWORK_DISRUPTION_PID=$!
  NETWORK_DISRUPTION_INTERFACE="${iface}"
}

restore_network_from_simulation() {
  if [ -n "${NETWORK_DISRUPTION_INTERFACE}" ]; then
    ip link set "${NETWORK_DISRUPTION_INTERFACE}" up 2>/dev/null || true
  fi

  if [ -n "${NETWORK_DISRUPTION_PID}" ]; then
    wait "${NETWORK_DISRUPTION_PID}" 2>/dev/null || true
    NETWORK_DISRUPTION_PID=""
  fi
}
