#!/bin/bash
# Copyright (C) 2015, Wazuh Inc.
#
# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.
#
# Runs a matrix of install / start / credentials / certificates / removal cases against a built
# wazuh-dashboard package on a disposable VM, and prints a summary. Works on Debian-based (.deb)
# and RPM-based (.rpm) hosts: the family is taken from the package extension.
#
# Case IDs say what they need:
#   Dnn  dashboard only (--dashboard; D19/D20 also need --dashboard-previous).
#   Fnn  FULL setup: the dashboard with wazuh-indexer and wazuh-manager (--manager and --indexer),
#        installed in different orders. Only the dashboard's behaviour is asserted; what the
#        indexer and the manager do is recorded as [INFO]. With only --dashboard, no F case runs.
#
# THE HOST IS WIPED AFTER EVERY CASE: the packages are purged and /etc/wazuh-dashboard,
# /usr/share/wazuh-dashboard, /etc/wazuh (shared credentials file and CA) and the wazuh-dashboard
# user are removed -- and, when their packages were given, everything of wazuh-manager and
# wazuh-indexer. Run it only on a throwaway VM.
#
# Usage:
#   sudo ./vm-test-matrix.sh --dashboard <wazuh-dashboard.deb|.rpm> [options]
#   sudo ./vm-test-matrix.sh --dashboard <file> --manager <file> --indexer <file> [options]
#   sudo ./vm-test-matrix.sh --clean-only [--dashboard <file>] [--manager <file> --indexer <file>] [--force]
#
# Options:
#   --dashboard <file>    Dashboard package under test (required unless --list or --clean-only).
#   --dashboard-previous <file>
#                         Older 5.x dashboard package of the same family; enables the upgrade cases.
#   --manager <file>      wazuh-manager package; with --indexer, enables the FULL (F) cases.
#   --indexer <file>      wazuh-indexer package; with --manager, enables the FULL (F) cases.
#   --cases <ids>         Comma-separated case IDs to run (default: all), e.g. D01,F03.
#   --list                List the cases and exit.
#   --clean-only          Only wipe the host (the same cleanup every case ends with) and exit; no
#                         case runs. The family is taken from the packages when given, else from
#                         the host's package manager. wazuh-manager and wazuh-indexer are purged
#                         too only with --manager / --indexer (the files are not read) or --force.
#   --log-dir <dir>       Where per-case logs and the summary go (default: ./vm-test-results-<ts>).
#   --start-timeout <s>   Seconds to wait for the service to become active / serve TLS (default 180).
#   --skip-tls            Do not check that the dashboard serves its certificate over HTTPS.
#   --verbose             Also print each case's log to the console.
#   --force               Run even when wazuh-indexer or wazuh-manager is installed although
#                         their packages were not given; they are purged with everything else.
#
# Exit status: 0 when no case failed, 1 otherwise, 2 on a usage or pre-flight error.

set -uo pipefail

readonly NAME="wazuh-dashboard"
readonly INSTALL_DIR="/usr/share/${NAME}"
readonly CONFIG_DIR="/etc/${NAME}"
readonly CERTS_DIR="${CONFIG_DIR}/certs"
readonly CONFIG_FILE="${CONFIG_DIR}/opensearch_dashboards.yml"
readonly RESOLVER="${INSTALL_DIR}/bin/resolve-credentials"
readonly KEYSTORE_BIN="${INSTALL_DIR}/bin/opensearch-dashboards-keystore"
readonly WAZUH_DIR="/etc/wazuh"
readonly CREDENTIALS_FILE="${WAZUH_DIR}/credentials.env"
readonly CA_DIR="${WAZUH_DIR}/ca"
# Both packages ship the unit's environment file here; the unit also reads /etc/sysconfig.
readonly ENV_FILE="/etc/default/${NAME}"

readonly KIBANA_PASS="TestKibana1Password"
readonly WUI_PASS="TestWui1Password"

DASHBOARD_PKG=""
DASHBOARD_PREV_PKG=""
MANAGER_PKG=""
INDEXER_PKG=""
# 1 when cleanup may purge wazuh-manager / wazuh-indexer too: their packages were given, or --force.
SIBLINGS_MANAGED=0
CASE_STARTED=0
SELECTED=""
LIST_ONLY=0
CLEAN_ONLY=0
LOG_DIR=""
START_TIMEOUT=180
SKIP_TLS=0
VERBOSE=0
FORCE=0
FAMILY=""

# -----------------------------------------------------------------------------------------
# Case registry: ID | title | function | needs (dashboard, dashboard-previous or full)
# -----------------------------------------------------------------------------------------

CASES=(
  "D01|Fresh install on an empty host|case_fresh_install|dashboard"
  "D02|Start without credentials is refused|case_start_without_credentials|dashboard"
  "D03|Credentials in credentials.env before install|case_credentials_before_install|dashboard"
  "D04|Credentials added after install|case_credentials_after_install|dashboard"
  "D05|Credentials from the unit environment (aliases)|case_credentials_env_aliases|dashboard"
  "D06|Environment wins over credentials.env|case_env_beats_file|dashboard"
  "D07|Values the keystore would not store verbatim|case_invalid_values|dashboard"
  "D08|Refused credentials file (bad mode)|case_refused_credentials_file|dashboard"
  "D09|Keystore wins over credentials.env on restart|case_keystore_wins|dashboard"
  "D10|Password configured in opensearch_dashboards.yml|case_yml_password|dashboard"
  "D11|Existing shared CA with key is reused|case_existing_ca|dashboard"
  "D12|Anchor-only shared CA|case_anchor_only_ca|dashboard"
  "D13|Operator-supplied certificate pair is kept|case_operator_pair|dashboard"
  "D14|Partial certificate pair is refused|case_partial_pair|dashboard"
  "D15|Custom SANs and node name|case_custom_sans|dashboard"
  "D16|resolve-credentials --clear|case_clear|dashboard"
  "D17|Package removal / purge cleans the host|case_remove|dashboard"
  "D18|Reinstall after removal mints a new CA|case_reinstall|dashboard"
  "D19|Upgrade while running|case_upgrade_running|dashboard-previous"
  "D20|Upgrade while stopped|case_upgrade_stopped|dashboard-previous"
  "D21|No wazuh_core default host: wazuh-wui not needed|case_no_wazuh_host|dashboard"
  "F01|Install order: indexer, manager, dashboard|case_order_imd|full"
  "F02|Install order: indexer, dashboard, manager|case_order_idm|full"
  "F03|Install order: manager, indexer, dashboard|case_order_mid|full"
  "F04|Install order: manager, dashboard, indexer|case_order_mdi|full"
  "F05|Install order: dashboard, indexer, manager|case_order_dim|full"
  "F06|Install order: dashboard, manager, indexer|case_order_dmi|full"
  "F07|Dashboard purge with the manager and indexer left|case_full_remove|full"
  "F08|Dashboard reinstall with the manager and indexer|case_full_reinstall|full"
)

# -----------------------------------------------------------------------------------------
# Output and assertions
# -----------------------------------------------------------------------------------------

info() { echo "  [INFO] $*"; }
step() { echo; echo "==> $*"; }

# check <description> <command...>: runs the command; a failure aborts the case (set -e).
check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  [PASS] ${desc}"
  else
    echo "  [FAIL] ${desc}"
    return 1
  fi
}

# check_not <description> <command...>: the command must fail.
check_not() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  [FAIL] ${desc}"
    return 1
  else
    echo "  [PASS] ${desc}"
  fi
}

contains() { grep -qF -- "$2" <<<"$1"; }
perm_is() { [ "$(stat -c '%U:%G:%a' "$1" 2>/dev/null)" = "$2" ]; }
absent() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
same_file() { cmp -s "$1" "$2"; }
fingerprint() { openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null; }
sha() { sha256sum "$1" | awk '{print $1}'; }

# -----------------------------------------------------------------------------------------
# Package family driver
# -----------------------------------------------------------------------------------------

pkg_manager_rpm() {
  if command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  else echo rpm
  fi
}

# Installs the package file $1. Output goes to ${WORK}/install.out and to the log.
pkg_install() {
  local rc=0
  case "${FAMILY}" in
    deb) dpkg -i "$1" >"${WORK}/install.out" 2>&1 || rc=$? ;;
    rpm) rpm -ivh "$1" >"${WORK}/install.out" 2>&1 || rc=$? ;;
  esac
  cat "${WORK}/install.out"
  return "${rc}"
}

pkg_upgrade() {
  local rc=0
  case "${FAMILY}" in
    deb) dpkg -i "$1" >"${WORK}/install.out" 2>&1 || rc=$? ;;
    rpm) rpm -Uvh "$1" >"${WORK}/install.out" 2>&1 || rc=$? ;;
  esac
  cat "${WORK}/install.out"
  return "${rc}"
}

pkg_remove() {
  case "${FAMILY}" in
    deb) DEBIAN_FRONTEND=noninteractive apt-get purge -y "${NAME}" ;;
    rpm)
      local pm
      pm=$(pkg_manager_rpm)
      if [ "${pm}" = rpm ]; then rpm -e "${NAME}"; else "${pm}" remove -y "${NAME}"; fi
      ;;
  esac
}

# Installed, or (deb) removed with its configuration files still on the host.
pkg_present() {
  case "${FAMILY}" in
    deb)
      local status
      status=$(dpkg-query -W -f='${db:Status-Status}' "${NAME}" 2>/dev/null) || return 1
      [ -n "${status}" ] && [ "${status}" != "not-installed" ]
      ;;
    rpm) rpm -q --quiet "${NAME}" ;;
  esac
}

pkg_installed() {
  case "${FAMILY}" in
    deb) dpkg-query -W -f='${Status}' "${NAME}" 2>/dev/null | grep -q "install ok installed" ;;
    rpm) rpm -q --quiet "${NAME}" ;;
  esac
}

pkg_installed_version() {
  case "${FAMILY}" in
    deb) dpkg-query -W -f='${Version}' "${NAME}" 2>/dev/null ;;
    rpm) rpm -q --qf '%{VERSION}-%{RELEASE}' "${NAME}" 2>/dev/null ;;
  esac
}

pkg_file_version() {
  case "${FAMILY}" in
    deb) dpkg-deb -f "$1" Version 2>/dev/null ;;
    rpm) rpm -qp --qf '%{VERSION}-%{RELEASE}' "$1" 2>/dev/null ;;
  esac
}

# The same operations for any package name (the siblings), $1 the package name.
pkgname_present() {
  case "${FAMILY}" in
    deb)
      local status
      status=$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) || return 1
      [ -n "${status}" ] && [ "${status}" != "not-installed" ]
      ;;
    rpm) rpm -q --quiet "$1" ;;
  esac
}

pkgname_remove() {
  case "${FAMILY}" in
    deb) DEBIAN_FRONTEND=noninteractive apt-get purge -y "$1" ;;
    rpm)
      local pm
      pm=$(pkg_manager_rpm)
      if [ "${pm}" = rpm ]; then rpm -e "$1"; else "${pm}" remove -y "$1"; fi
      ;;
  esac
}

sibling_installed() {
  local sibling
  for sibling in wazuh-indexer wazuh-manager; do
    case "${FAMILY}" in
      deb) dpkg-query -W -f='${Status}' "${sibling}" 2>/dev/null | grep -q "installed" && return 0 ;;
      rpm) rpm -q --quiet "${sibling}" && return 0 ;;
    esac
  done
  return 1
}

# -----------------------------------------------------------------------------------------
# Service, keystore and resolver helpers
# -----------------------------------------------------------------------------------------

svc_start() {
  systemctl daemon-reload
  timeout 120 systemctl start "${NAME}"
}

# Restart=always keeps retrying a failed start, and StartLimitBurst then blocks the next one:
# stop it and clear the rate limit.
svc_stop() {
  systemctl stop "${NAME}" >/dev/null 2>&1 || true
  systemctl reset-failed "${NAME}" >/dev/null 2>&1 || true
}

svc_start_refused() {
  if svc_start; then
    svc_stop
    return 1
  fi
  svc_stop
  return 0
}

# Active, and still active with no restart after a settle period.
wait_active() {
  local deadline=$((SECONDS + START_TIMEOUT)) restarts
  until [ "$(systemctl is-active "${NAME}" 2>/dev/null)" = active ]; do
    [ "${SECONDS}" -lt "${deadline}" ] || return 1
    sleep 2
  done
  restarts=$(systemctl show -p NRestarts --value "${NAME}" 2>/dev/null || echo 0)
  sleep 10
  [ "$(systemctl is-active "${NAME}" 2>/dev/null)" = active ] &&
    [ "$(systemctl show -p NRestarts --value "${NAME}" 2>/dev/null || echo 0)" = "${restarts}" ]
}

server_port() {
  local port
  port=$(awk -F: '/^server\.port:/ { gsub(/[ \t'"'"'"]/, "", $2); print $2 }' "${CONFIG_FILE}" 2>/dev/null)
  echo "${port:-443}"
}

# The dashboard serves HTTPS with certs/dashboard.pem (it listens even without an indexer).
wait_tls() {
  local deadline=$((SECONDS + START_TIMEOUT)) port expected served
  port=$(server_port)
  expected=$(fingerprint "${CERTS_DIR}/dashboard.pem")
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    served=$(openssl s_client -connect "127.0.0.1:${port}" -servername localhost </dev/null 2>/dev/null |
      openssl x509 -noout -fingerprint -sha256 2>/dev/null || true)
    if [ -n "${served}" ]; then
      [ "${served}" = "${expected}" ]
      return
    fi
    sleep 3
  done
  return 1
}

check_running() {
  check "service is active and stable" wait_active
  if [ "${SKIP_TLS}" -eq 0 ]; then
    check "HTTPS on port $(server_port) serves certs/dashboard.pem" wait_tls
  fi
}

# Prints the keystore entry names. Stderr goes to ${WORK}/keystore.err, so a failed call can be
# told apart from a missing entry.
ks_list() {
  (cd / && runuser -u "${NAME}" -- "${KEYSTORE_BIN}" list) </dev/null 2>"${WORK}/keystore.err"
}

# The listing is captured before it is searched, and a miss says why: the CLI's exit status, its
# stderr and the entry names it printed (names only, never values).
ks_has() {
  local keys rc=0
  keys=$(ks_list) || rc=$?
  if [ "${rc}" -eq 0 ] && grep -qxF -- "$1" <<<"${keys}"; then
    return 0
  fi
  echo "  [DEBUG] $(date -u +%H:%M:%S.%N | cut -c1-12) keystore has no $1 (list exit status ${rc})"
  [ -s "${WORK}/keystore.err" ] && sed 's/^/  [DEBUG]   stderr: /' "${WORK}/keystore.err"
  sed 's/^/  [DEBUG]   entry: /' <<<"${keys}"
  return 1
}

# Runs the pre-start step by hand; sets PRE_OUT and PRE_RC. Extra arguments are VAR=value pairs.
PRE_OUT=""
PRE_RC=0
prestart() {
  PRE_RC=0
  PRE_OUT=$(env "$@" "${RESOLVER}" --prestart 2>&1) || PRE_RC=$?
  echo "${PRE_OUT}"
  echo "  (prestart exit status ${PRE_RC})"
}

prestart_rc_is() { [ "${PRE_RC}" -eq "$1" ]; }

# write_creds <kibanaserver> <wazuh-wui> [mode]; an empty value leaves the key out.
write_creds() {
  install -d -m 0700 -o root -g root "${WAZUH_DIR}"
  {
    [ -n "$1" ] && printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\n' "$1"
    [ -n "$2" ] && printf 'WAZUH_MANAGER_WUI_PASSWORD=%s\n' "$2"
    true
  } >"${CREDENTIALS_FILE}"
  chown root:root "${CREDENTIALS_FILE}"
  chmod "${3:-0600}" "${CREDENTIALS_FILE}"
}

install_ok() {
  check "package installs" pkg_install "$1"
  check "package is registered as installed" pkg_installed
}

journal_since() {
  journalctl -u "${NAME}" --since "@$1" --no-pager 2>/dev/null || true
}

# Checks every entry, so a failure names each one that is missing.
has_all_consumed_entries() {
  local entry rc=0
  for entry in opensearch.username opensearch.password wazuh_core.hosts.default.password; do
    ks_has "${entry}" || rc=1
  done
  return "${rc}"
}

# Stages a self-signed CA and a leaf pair signed by it into certs/ (operator-supplied material).
# $1: "pair" (dashboard.pem + key + root-ca.pem) or "cert-only" (dashboard.pem alone).
stage_operator_certs() {
  local what="$1" d="${WORK}/operator" owner=root:root
  mkdir -p "${d}"
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
    -keyout "${d}/ca.key" -out "${d}/ca.pem" -subj "/CN=Test Operator CA" >/dev/null 2>&1
  openssl req -new -newkey rsa:2048 -nodes -sha256 \
    -keyout "${d}/leaf.key" -out "${d}/leaf.csr" -subj "/CN=operator-dashboard" >/dev/null 2>&1
  printf '%s\n' 'basicConstraints=CA:FALSE' 'keyUsage=digitalSignature,keyEncipherment' \
    'extendedKeyUsage=serverAuth,clientAuth' 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
    >"${d}/leaf.ext"
  openssl x509 -req -sha256 -days 30 -in "${d}/leaf.csr" -CA "${d}/ca.pem" -CAkey "${d}/ca.key" \
    -CAcreateserial -extfile "${d}/leaf.ext" -out "${d}/leaf.pem" >/dev/null 2>&1

  id "${NAME}" >/dev/null 2>&1 && owner="${NAME}:${NAME}"
  install -d -m 0755 "${CONFIG_DIR}"
  install -d -m 0700 "${CERTS_DIR}"
  install -m 0400 "${d}/leaf.pem" "${CERTS_DIR}/dashboard.pem"
  if [ "${what}" = pair ]; then
    install -m 0400 "${d}/leaf.key" "${CERTS_DIR}/dashboard-key.pem"
    install -m 0400 "${d}/ca.pem" "${CERTS_DIR}/root-ca.pem"
  fi
  chown -R "${owner}" "${CERTS_DIR}"
  chmod 0500 "${CERTS_DIR}"
}

# Saves the CA minted by an install into ${WORK}/saved-ca, with the modes of the directories and
# files. The library requires root:root, which the restore sets explicitly rather than trusting the
# copy: a copy that went through a shared folder (vboxsf, 9p) comes back owned by someone else.
save_minted_ca() {
  rm -rf "${WORK}/saved-ca"
  mkdir -m 0700 "${WORK}/saved-ca"
  cp -p "${CA_DIR}"/root-ca.* "${WORK}/saved-ca/"
  {
    stat -c '%a %n' "${WAZUH_DIR}" "${CA_DIR}"
    stat -c '%a %n' "${CA_DIR}"/root-ca.*
  } >"${WORK}/saved-ca.modes"
  cat "${WORK}/saved-ca.modes"
}

saved_mode() { awk -v p="$1" '$2 == p { print $1 }' "${WORK}/saved-ca.modes"; }

# restore_ca <file...>: recreates /etc/wazuh and its CA directory with the saved modes, root:root,
# and puts back only the named files (root-ca.pem, root-ca.key, ...).
restore_ca() {
  local f
  install -d -m "$(saved_mode "${WAZUH_DIR}")" -o root -g root "${WAZUH_DIR}"
  install -d -m "$(saved_mode "${CA_DIR}")" -o root -g root "${CA_DIR}"
  for f in "$@"; do
    install -m "$(saved_mode "${CA_DIR}/${f}")" -o root -g root "${WORK}/saved-ca/${f}" "${CA_DIR}/${f}"
  done
  ls -la "${CA_DIR}"
}

# -----------------------------------------------------------------------------------------
# Host cleanup
# -----------------------------------------------------------------------------------------

readonly MANAGER="wazuh-manager"
readonly INDEXER="wazuh-indexer"
readonly MANAGER_DIR="/var/wazuh-manager"
readonly MANAGER_CA="${MANAGER_DIR}/etc/certs/root-ca.pem"
readonly INDEXER_CA="/etc/wazuh-indexer/certs/root-ca.pem"
readonly INDEXER_SECURITY_INIT="/usr/share/wazuh-indexer/bin/indexer-security-init.sh"

# Purges the manager and the indexer and whatever their packages leave behind.
clean_siblings() {
  local sib
  for sib in "${MANAGER}" "${INDEXER}"; do
    systemctl stop "${sib}" >/dev/null 2>&1 || true
    systemctl disable "${sib}" >/dev/null 2>&1 || true
    systemctl reset-failed "${sib}" >/dev/null 2>&1 || true
    if pkgname_present "${sib}"; then
      pkgname_remove "${sib}" >/dev/null 2>&1 || true
      if [ "${FAMILY}" = deb ] && pkgname_present "${sib}"; then
        dpkg --purge --force-all "${sib}" >/dev/null 2>&1 || true
      fi
      if [ "${FAMILY}" = rpm ] && pkgname_present "${sib}"; then
        rpm -e --noscripts "${sib}" >/dev/null 2>&1 || true
      fi
    fi
    if id "${sib}" >/dev/null 2>&1; then userdel -f "${sib}" >/dev/null 2>&1 || true; fi
    if getent group "${sib}" >/dev/null 2>&1; then groupdel "${sib}" >/dev/null 2>&1 || true; fi
  done
  rm -rf "${MANAGER_DIR}" /etc/wazuh-indexer /usr/share/wazuh-indexer /var/lib/wazuh-indexer \
    /var/log/wazuh-indexer /run/wazuh-indexer
}

clean_host() {
  if [ "${SIBLINGS_MANAGED}" -eq 1 ]; then clean_siblings; fi
  systemctl stop "${NAME}" >/dev/null 2>&1 || true
  systemctl disable "${NAME}" >/dev/null 2>&1 || true
  systemctl reset-failed "${NAME}" >/dev/null 2>&1 || true

  if pkg_present; then
    pkg_remove >/dev/null 2>&1 || true
    if [ "${FAMILY}" = deb ] && pkg_present; then
      dpkg --purge --force-all "${NAME}" >/dev/null 2>&1 || true
    fi
    if [ "${FAMILY}" = rpm ] && pkg_present; then
      rpm -e --noscripts "${NAME}" >/dev/null 2>&1 || true
    fi
  fi

  rm -rf "${CONFIG_DIR}" "${INSTALL_DIR}" "${WAZUH_DIR}" "/run/${NAME}" "/var/run/${NAME}" \
    "/var/log/${NAME}" "/var/lib/${NAME}"
  rm -f "${ENV_FILE}" "/etc/sysconfig/${NAME}" "/etc/init.d/${NAME}" \
    "/etc/systemd/system/${NAME}.service" "/usr/lib/systemd/system/${NAME}.service" \
    "/lib/systemd/system/${NAME}.service"
  if id "${NAME}" >/dev/null 2>&1; then userdel -f "${NAME}" >/dev/null 2>&1 || true; fi
  if getent group "${NAME}" >/dev/null 2>&1; then groupdel "${NAME}" >/dev/null 2>&1 || true; fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed "${NAME}" >/dev/null 2>&1 || true

  # Self-check: the next case must start from a clean host.
  local dirty=""
  pkg_present && dirty="${dirty} package"
  for p in "${CONFIG_DIR}" "${INSTALL_DIR}" "${WAZUH_DIR}"; do
    absent "${p}" || dirty="${dirty} ${p}"
  done
  id "${NAME}" >/dev/null 2>&1 && dirty="${dirty} user"
  getent group "${NAME}" >/dev/null 2>&1 && dirty="${dirty} group"
  if [ "${SIBLINGS_MANAGED}" -eq 1 ]; then
    local sib
    for sib in "${MANAGER}" "${INDEXER}"; do
      pkgname_present "${sib}" && dirty="${dirty} ${sib}"
      id "${sib}" >/dev/null 2>&1 && dirty="${dirty} ${sib}-user"
    done
    for p in "${MANAGER_DIR}" /etc/wazuh-indexer /usr/share/wazuh-indexer; do
      absent "${p}" || dirty="${dirty} ${p}"
    done
  fi
  if [ -n "${dirty}" ]; then
    echo "  [FAIL] host not clean after cleanup:${dirty}"
    return 1
  fi
  echo "  [INFO] host cleaned"
}

# -----------------------------------------------------------------------------------------
# Cases
# -----------------------------------------------------------------------------------------

case_fresh_install() {
  step "Install on an empty host"
  install_ok "${DASHBOARD_PKG}"
  check "user ${NAME} exists" id "${NAME}"
  check "resolver is root:root 750" perm_is "${RESOLVER}" root:root:750
  check "lib/ is root:${NAME} 750" perm_is "${INSTALL_DIR}/lib" "root:${NAME}:750"
  check "shared library is root:${NAME} 640" perm_is "${INSTALL_DIR}/lib/wazuh-credentials.sh" "root:${NAME}:640"
  check "${WAZUH_DIR} is root:root 700" perm_is "${WAZUH_DIR}" root:root:700
  check "empty credentials.env is root:root 600" perm_is "${CREDENTIALS_FILE}" root:root:600
  check "credentials.env is empty" test ! -s "${CREDENTIALS_FILE}"

  step "Certificates issued from a freshly minted shared CA"
  check "shared CA certificate minted" test -f "${CA_DIR}/root-ca.pem"
  check "shared CA key minted" test -f "${CA_DIR}/root-ca.key"
  check "certs/ is ${NAME} 500" perm_is "${CERTS_DIR}" "${NAME}:${NAME}:500"
  local f
  for f in dashboard.pem dashboard-key.pem root-ca.pem; do
    check "certs/${f} is ${NAME} 400" perm_is "${CERTS_DIR}/${f}" "${NAME}:${NAME}:400"
  done
  check "certs/root-ca.pem is the shared CA" same_file "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/root-ca.pem"
  check "dashboard.pem chains to the shared CA for server use" \
    openssl verify -purpose sslserver -CAfile "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/dashboard.pem"

  step "Keystore after install without credentials"
  check "keystore exists" test -f "${CONFIG_DIR}/opensearch_dashboards.keystore"
  check "AI assistant encryption key generated" ks_has wazuh_ai_assistant.encryptionKey
  check_not "opensearch.password not stored" ks_has opensearch.password
  check_not "wazuh_core.hosts.default.password not stored" ks_has wazuh_core.hosts.default.password
}

case_start_without_credentials() {
  install_ok "${DASHBOARD_PKG}"
  systemctl enable "${NAME}" >/dev/null 2>&1
  step "Start without peer credentials"
  check "systemctl start is refused" svc_start_refused
  prestart
  check "prestart exits 1" prestart_rc_is 1
  check "reports MISSING WAZUH_INDEXER_KIBANASERVER_PASSWORD" \
    contains "${PRE_OUT}" "MISSING WAZUH_INDEXER_KIBANASERVER_PASSWORD"
  check "reports MISSING WAZUH_MANAGER_WUI_PASSWORD" \
    contains "${PRE_OUT}" "MISSING WAZUH_MANAGER_WUI_PASSWORD"
}

case_credentials_before_install() {
  step "Credentials published before the dashboard is installed"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${DASHBOARD_PKG}"
  check "install stored opensearch.password" ks_has opensearch.password
  check "install stored opensearch.username" ks_has opensearch.username
  check "install stored wazuh_core.hosts.default.password" ks_has wazuh_core.hosts.default.password
  check "credentials.env was left untouched" \
    grep -qx "WAZUH_INDEXER_KIBANASERVER_PASSWORD=${KIBANA_PASS}" "${CREDENTIALS_FILE}"
  step "Start"
  systemctl enable "${NAME}" >/dev/null 2>&1
  check "systemctl start succeeds" svc_start
  check_running
}

case_credentials_after_install() {
  install_ok "${DASHBOARD_PKG}"
  step "First start without credentials"
  check "systemctl start is refused" svc_start_refused
  step "The indexer and the manager publish their credentials later"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  check "systemctl start succeeds" svc_start
  check_running
  check "keystore holds every consumed entry" has_all_consumed_entries
}

case_credentials_env_aliases() {
  install_ok "${DASHBOARD_PKG}"
  step "Credentials through the unit's EnvironmentFile, wazuh-docker aliases"
  printf 'INDEXER_PASSWORD=%s\nAPI_PASSWORD=%s\n' "${KIBANA_PASS}" "${WUI_PASS}" >>"${ENV_FILE}"
  local ts
  ts=$(date +%s)
  check "systemctl start succeeds" svc_start
  check_running
  check "keystore holds every consumed entry" has_all_consumed_entries
  local journal
  journal=$(journal_since "${ts}")
  if [ -n "${journal}" ]; then
    check "journal says the value came from INDEXER_PASSWORD" \
      contains "${journal}" "from the environment (INDEXER_PASSWORD)"
    check "journal says the value came from API_PASSWORD" \
      contains "${journal}" "from the environment (API_PASSWORD)"
  else
    info "journal not available; source of the values not checked"
  fi
}

case_env_beats_file() {
  install_ok "${DASHBOARD_PKG}"
  step "Valid values in the environment, an invalid one in credentials.env"
  write_creds "123456789e10" "${WUI_PASS}"
  printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\n' "${KIBANA_PASS}" >>"${ENV_FILE}"
  check "systemctl start succeeds (the environment wins)" svc_start
  check_running
  check "keystore holds every consumed entry" has_all_consumed_entries
}

case_invalid_values() {
  install_ok "${DASHBOARD_PKG}"
  local value
  for value in '123456789e10' 'true' '"Quoted1Password"' '[1]' ' Leading1Password' \
    'Trailing1Password '; do
    step "kibanaserver password <${value}> from the environment"
    prestart WAZUH_INDEXER_KIBANASERVER_PASSWORD="${value}" WAZUH_MANAGER_WUI_PASSWORD="${WUI_PASS}"
    check "prestart exits 1" prestart_rc_is 1
    check "reports INVALID WAZUH_INDEXER_KIBANASERVER_PASSWORD" \
      contains "${PRE_OUT}" "INVALID WAZUH_INDEXER_KIBANASERVER_PASSWORD"
    check_not "opensearch.password was not stored" ks_has opensearch.password
    case "${value}" in
      true|'[1]') ;;
      *) check_not "the value is never printed" contains "${PRE_OUT}" "${value}" ;;
    esac
  done

  step "Invalid value in credentials.env blocks the service"
  write_creds "123456789e10" "${WUI_PASS}"
  check "systemctl start is refused" svc_start_refused
  prestart
  check "reports INVALID WAZUH_INDEXER_KIBANASERVER_PASSWORD" \
    contains "${PRE_OUT}" "INVALID WAZUH_INDEXER_KIBANASERVER_PASSWORD"
}

case_refused_credentials_file() {
  install_ok "${DASHBOARD_PKG}"
  step "credentials.env readable by everyone (0644)"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}" 0644
  check "systemctl start is refused" svc_start_refused
  prestart
  check "prestart exits 1" prestart_rc_is 1
  check "reports the file as REFUSED" contains "${PRE_OUT}" "REFUSED ${CREDENTIALS_FILE}"
  check_not "opensearch.password was not stored" ks_has opensearch.password
  step "Fixing the mode lets it start"
  chmod 0600 "${CREDENTIALS_FILE}"
  check "systemctl start succeeds" svc_start
  check_running
}

case_keystore_wins() {
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${DASHBOARD_PKG}"
  check "systemctl start succeeds" svc_start
  check_running
  step "credentials.env changes to a value that would be invalid; restart"
  write_creds "123456789e10" "${WUI_PASS}"
  check "systemctl restart succeeds" timeout 120 systemctl restart "${NAME}"
  check_running
  prestart
  check "prestart exits 0" prestart_rc_is 0
  check "credentials.env is ignored once the keystore has the entry" \
    contains "${PRE_OUT}" "opensearch.password is already in the keystore"
}

case_yml_password() {
  install_ok "${DASHBOARD_PKG}"
  step "opensearch.password set by the operator in opensearch_dashboards.yml"
  printf '\nopensearch.password: YmlKibana1Password\n' >>"${CONFIG_FILE}"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  prestart
  check "prestart exits 0" prestart_rc_is 0
  check "reports the yml setting" contains "${PRE_OUT}" "opensearch.password is set in ${CONFIG_FILE}"
  check_not "opensearch.password not written to the keystore" ks_has opensearch.password
  check_not "opensearch.username not written to the keystore" ks_has opensearch.username
  check "wazuh_core.hosts.default.password stored" ks_has wazuh_core.hosts.default.password
  check "systemctl start succeeds" svc_start
  check_running
}

case_existing_ca() {
  step "Mint a CA with a first install, then wipe everything but the CA"
  install_ok "${DASHBOARD_PKG}"
  save_minted_ca
  local ca_fp
  ca_fp=$(fingerprint "${CA_DIR}/root-ca.pem")
  clean_host
  restore_ca root-ca.pem root-ca.key

  step "Install with the shared CA already present"
  install_ok "${DASHBOARD_PKG}"
  check "install reuses the shared CA" contains "$(cat "${WORK}/install.out")" "reusing the shared root CA"
  check "shared CA is unchanged" test "$(fingerprint "${CA_DIR}/root-ca.pem")" = "${ca_fp}"
  check "certs/root-ca.pem is the shared CA" same_file "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/root-ca.pem"
  check "dashboard.pem chains to the existing CA" \
    openssl verify -purpose sslserver -CAfile "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/dashboard.pem"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  check "systemctl start succeeds" svc_start
  check_running
}

case_anchor_only_ca() {
  step "Mint a CA, then keep only its certificate (a CA managed elsewhere)"
  install_ok "${DASHBOARD_PKG}"
  save_minted_ca
  clean_host
  restore_ca root-ca.pem

  step "Install with an anchor-only shared CA"
  check "package installs despite the missing CA key" pkg_install "${DASHBOARD_PKG}"
  local out
  out=$(cat "${WORK}/install.out")
  check "install reports the CA cannot issue" contains "${out}" "has no private key"
  check "install warns the dashboard has no certificates" \
    contains "${out}" "the dashboard has no TLS certificates"
  check "certs/root-ca.pem is the anchor" same_file "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/root-ca.pem"
  check "no dashboard.pem issued" absent "${CERTS_DIR}/dashboard.pem"
  check "no dashboard-key.pem issued" absent "${CERTS_DIR}/dashboard-key.pem"
  check "no CA key was created" absent "${CA_DIR}/root-ca.key"
}

case_operator_pair() {
  step "Operator stages their own certificate pair before installing"
  stage_operator_certs pair
  local cert_sha key_sha ca_sha
  cert_sha=$(sha "${CERTS_DIR}/dashboard.pem")
  key_sha=$(sha "${CERTS_DIR}/dashboard-key.pem")
  ca_sha=$(sha "${CERTS_DIR}/root-ca.pem")
  install_ok "${DASHBOARD_PKG}"
  check "install keeps the existing pair" \
    contains "$(cat "${WORK}/install.out")" "already holds a certificate pair"
  check "dashboard.pem unchanged" test "$(sha "${CERTS_DIR}/dashboard.pem")" = "${cert_sha}"
  check "dashboard-key.pem unchanged" test "$(sha "${CERTS_DIR}/dashboard-key.pem")" = "${key_sha}"
  check "root-ca.pem unchanged" test "$(sha "${CERTS_DIR}/root-ca.pem")" = "${ca_sha}"
  check "no shared CA minted over operator material" absent "${CA_DIR}/root-ca.pem"

  # Staged on a host without the service user, so root's until the package takes it over -- which
  # is what the installation assistant does. The service reads the pair after dropping privileges.
  step "The staged pair is the service user's and the dashboard starts with it"
  local f
  for f in dashboard.pem dashboard-key.pem root-ca.pem; do
    check "certs/${f} is owned by ${NAME}" test "$(stat -c '%U:%G' "${CERTS_DIR}/${f}")" = "${NAME}:${NAME}"
  done
  check "certs/ is owned by ${NAME}" test "$(stat -c '%U:%G' "${CERTS_DIR}")" = "${NAME}:${NAME}"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  check "systemctl start succeeds" svc_start
  check_running
}

case_partial_pair() {
  step "Only dashboard.pem is staged before installing"
  stage_operator_certs cert-only
  check "package installs" pkg_install "${DASHBOARD_PKG}"
  check "install refuses to complete the pair" \
    contains "$(cat "${WORK}/install.out")" "refusing to complete it"
  check "no dashboard-key.pem created" absent "${CERTS_DIR}/dashboard-key.pem"
  check "no shared CA minted" absent "${CA_DIR}/root-ca.pem"
}

case_custom_sans() {
  step "Install with WAZUH_DASHBOARD_CERT_SANS and WAZUH_DASHBOARD_NODE_NAME"
  export WAZUH_DASHBOARD_CERT_SANS="DNS:dash.test,IP:10.9.8.7"
  export WAZUH_DASHBOARD_NODE_NAME="dash-node"
  install_ok "${DASHBOARD_PKG}"
  unset WAZUH_DASHBOARD_CERT_SANS WAZUH_DASHBOARD_NODE_NAME
  local sans subject count
  sans=$(openssl x509 -in "${CERTS_DIR}/dashboard.pem" -noout -text |
    sed -n '/X509v3 Subject Alternative Name:/{n;s/^ *//p;}')
  subject=$(openssl x509 -in "${CERTS_DIR}/dashboard.pem" -noout -subject)
  info "SANs: ${sans}"
  info "${subject}"
  check "CN is the node name" contains "${subject}" "CN = dash-node"
  check "SAN DNS:dash.test" contains "${sans}" "DNS:dash.test"
  check "SAN IP 10.9.8.7" contains "${sans}" "IP Address:10.9.8.7"
  check "SAN DNS:localhost (always added)" contains "${sans}" "DNS:localhost"
  check "SAN IP 127.0.0.1 (always added)" contains "${sans}" "IP Address:127.0.0.1"
  count=$(tr ',' '\n' <<<"${sans}" | grep -c ':')
  check "exactly 5 SANs (the list plus loopback, no discovery)" test "${count}" -eq 5
}

case_clear() {
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${DASHBOARD_PKG}"
  check "systemctl start succeeds" svc_start
  check_running
  step "--clear while the dashboard runs"
  local out rc=0
  out=$("${RESOLVER}" --clear 2>&1) || rc=$?
  echo "${out}"
  check "--clear is refused" test "${rc}" -ne 0
  check "refusal is explained" contains "${out}" "refusing to clear credentials while the dashboard is running"
  check "keystore still holds the entries" has_all_consumed_entries
  step "--clear after stopping"
  svc_stop
  rc=0
  out=$("${RESOLVER}" --clear 2>&1) || rc=$?
  echo "${out}"
  check "--clear succeeds" test "${rc}" -eq 0
  local entry
  for entry in opensearch.username opensearch.password wazuh_core.hosts.default.password \
    wazuh_ai_assistant.encryptionKey; do
    check_not "${entry} removed" ks_has "${entry}"
  done
  local f
  for f in dashboard.pem dashboard-key.pem root-ca.pem; do
    check "certs/${f} removed" absent "${CERTS_DIR}/${f}"
  done
  check "minted CA removed" absent "${CA_DIR}/root-ca.key"
  check "credentials.env kept (owned by the siblings)" test -f "${CREDENTIALS_FILE}"
}

case_remove() {
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${DASHBOARD_PKG}"
  check "systemctl start succeeds" svc_start
  check_running
  step "Remove the package (${FAMILY}: $([ "${FAMILY}" = deb ] && echo purge || echo erase))"
  check "package removal succeeds" pkg_remove
  check_not "package no longer registered" pkg_present
  check_not "service no longer active" systemctl is-active --quiet "${NAME}"
  check "${INSTALL_DIR} removed" absent "${INSTALL_DIR}"
  check "${WAZUH_DIR} removed (no other Wazuh component)" absent "${WAZUH_DIR}"
  check_not "user ${NAME} removed" id "${NAME}"
  check_not "group ${NAME} removed" getent group "${NAME}"
  if [ "${FAMILY}" = deb ]; then
    check "${CONFIG_DIR} removed by purge" absent "${CONFIG_DIR}"
  elif absent "${CONFIG_DIR}"; then
    info "${CONFIG_DIR} removed"
  else
    info "${CONFIG_DIR} left behind by rpm (not a failure):"
    find "${CONFIG_DIR}" -maxdepth 2 | sed 's/^/         /'
  fi
}

case_reinstall() {
  install_ok "${DASHBOARD_PKG}"
  local ca_fp
  ca_fp=$(fingerprint "${CA_DIR}/root-ca.pem")
  step "Remove with the package's own scripts, then reinstall"
  check "package removal succeeds" pkg_remove
  check "${WAZUH_DIR} removed with the last component" absent "${WAZUH_DIR}"
  # rpm may leave config files behind (.rpmsave); a reinstall must start from its own defaults.
  [ "${FAMILY}" = rpm ] && rm -rf "${CONFIG_DIR}"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${DASHBOARD_PKG}"
  check "a new shared CA was minted" test "$(fingerprint "${CA_DIR}/root-ca.pem")" != "${ca_fp}"
  check "dashboard.pem chains to the new CA" \
    openssl verify -purpose sslserver -CAfile "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/dashboard.pem"
  check "systemctl start succeeds" svc_start
  check_running
}

# Installs --dashboard-previous with credentials and makes sure it has certificates (an older 5.x build may
# not issue them), leaving it stopped.
install_previous() {
  step "Install the previous package ($(pkg_file_version "${DASHBOARD_PREV_PKG}"))"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${DASHBOARD_PREV_PKG}"
  if [ ! -f "${CERTS_DIR}/dashboard.pem" ]; then
    info "the previous package issued no certificates; staging an operator pair"
    rm -rf "${CERTS_DIR}"
    stage_operator_certs pair
  fi
  systemctl enable "${NAME}" >/dev/null 2>&1
}

case_upgrade_running() {
  install_previous
  check "previous version starts" svc_start
  check "previous version is active" wait_active
  local cert_sha key_sha expected
  cert_sha=$(sha "${CERTS_DIR}/dashboard.pem")
  key_sha=$(sha "${CERTS_DIR}/dashboard-key.pem")
  expected=$(pkg_file_version "${DASHBOARD_PKG}")
  step "Upgrade to ${expected} while running"
  check "upgrade succeeds" pkg_upgrade "${DASHBOARD_PKG}"
  check "installed version is ${expected}" test "$(pkg_installed_version)" = "${expected}"
  check_running
  check "dashboard.pem unchanged by the upgrade" test "$(sha "${CERTS_DIR}/dashboard.pem")" = "${cert_sha}"
  check "dashboard-key.pem unchanged by the upgrade" test "$(sha "${CERTS_DIR}/dashboard-key.pem")" = "${key_sha}"
  check "keystore holds every consumed entry" has_all_consumed_entries
}

case_upgrade_stopped() {
  install_previous
  local expected
  expected=$(pkg_file_version "${DASHBOARD_PKG}")
  step "Upgrade to ${expected} while stopped"
  check "upgrade succeeds" pkg_upgrade "${DASHBOARD_PKG}"
  check "installed version is ${expected}" test "$(pkg_installed_version)" = "${expected}"
  sleep 5
  check_not "service was not started by the upgrade" systemctl is-active --quiet "${NAME}"
  check "systemctl start succeeds" svc_start
  check_running
}

case_no_wazuh_host() {
  install_ok "${DASHBOARD_PKG}"
  # wazuh_core.hosts itself is required by the plugin's config schema (the dashboard exits with a
  # fatal ValidationError without it), so the host is renamed rather than removed, and carries its
  # own password in the yml.
  step "Rename the wazuh_core default host in opensearch_dashboards.yml; publish only kibanaserver"
  sed -i '/^wazuh_core\.hosts:/,$ s/^  default:$/  manager:/' "${CONFIG_FILE}"
  printf '    password: YmlWui1Password\n' >>"${CONFIG_FILE}"
  sed -n '/^wazuh_core\.hosts:/,$p' "${CONFIG_FILE}"
  check "the yml has no wazuh_core.hosts.default" test -z "$(grep -n '^  default:$' "${CONFIG_FILE}")"
  write_creds "${KIBANA_PASS}" ""
  prestart
  check "prestart exits 0" prestart_rc_is 0
  check "reports wazuh-wui is not needed" contains "${PRE_OUT}" "WAZUH_MANAGER_WUI_PASSWORD is not needed"
  check_not "no wazuh_core password written" ks_has wazuh_core.hosts.default.password
  check "systemctl start succeeds" svc_start
  check_running
}

# -----------------------------------------------------------------------------------------
# FULL setup: the dashboard with the manager and the indexer
#
# Only the dashboard is asserted. The siblings are installed with a check (a case means nothing
# without them), but whether they start is recorded as [INFO]: the manager does not start without
# WAZUH_INDEXER_MANAGER_PASSWORD, and the indexer publishes no key and uses its own CA -- theirs to
# fix. The dashboard is expected to follow credentials.env exactly: what is published there is
# resolved, what is not is named, and it starts only when both of its keys are resolved.
# -----------------------------------------------------------------------------------------

has_key() { [ -f "${CREDENTIALS_FILE}" ] && grep -Eq "^(export )?$1=" "${CREDENTIALS_FILE}"; }

# sib_install <file> <name> [VAR=value...]: installs a sibling package. Its output goes to the log
# and to ${WORK}/install-<name>.out; the dashboard's install.out is left alone.
sib_install() {
  local file="$1" name="$2" rc=0
  shift 2
  case "${FAMILY}" in
    deb) env "$@" dpkg -i "${file}" >"${WORK}/install-${name}.out" 2>&1 || rc=$? ;;
    rpm) env "$@" rpm -ivh "${file}" >"${WORK}/install-${name}.out" 2>&1 || rc=$? ;;
  esac
  cat "${WORK}/install-${name}.out"
  return "${rc}"
}

# Installs the indexer with its demo certificates, starts it, waits for 9200 and initialises its
# security index. Everything after the install is [INFO].
indexer_up() {
  step "Install and start ${INDEXER}"
  check "${INDEXER} installs" sib_install "${INDEXER_PKG}" "${INDEXER}" GENERATE_CERTS=true
  if has_key WAZUH_INDEXER_KIBANASERVER_PASSWORD; then
    info "${INDEXER} published WAZUH_INDEXER_KIBANASERVER_PASSWORD"
  else
    info "${INDEXER} did not publish WAZUH_INDEXER_KIBANASERVER_PASSWORD"
  fi
  systemctl daemon-reload
  if timeout 200 systemctl enable --now "${INDEXER}" >/dev/null 2>&1; then
    info "${INDEXER} started"
  else
    info "${INDEXER} did not start: $(systemctl is-active "${INDEXER}" 2>/dev/null)"
    return 0
  fi
  local deadline=$((SECONDS + START_TIMEOUT)) code="000"
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    code=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:9200 2>/dev/null || true)
    [ "${code}" != "000" ] && break
    sleep 3
  done
  info "${INDEXER} on 9200 answers HTTP ${code}"
  if [ -x "${INDEXER_SECURITY_INIT}" ] &&
     timeout 300 "${INDEXER_SECURITY_INIT}" >"${WORK}/indexer-security-init.out" 2>&1; then
    info "indexer-security-init.sh succeeded"
  else
    info "indexer-security-init.sh failed or is missing: $(tail -n 1 "${WORK}/indexer-security-init.out" 2>/dev/null)"
  fi
}

# Installs the manager and tries to start it; the start is [INFO].
manager_up() {
  step "Install and start ${MANAGER}"
  check "${MANAGER} installs" sib_install "${MANAGER_PKG}" "${MANAGER}"
  if has_key WAZUH_MANAGER_WUI_PASSWORD; then
    info "${MANAGER} published WAZUH_MANAGER_WUI_PASSWORD"
  else
    info "${MANAGER} did not publish WAZUH_MANAGER_WUI_PASSWORD"
  fi
  systemctl daemon-reload
  local ts
  ts=$(date +%s)
  if timeout 120 systemctl start "${MANAGER}" >/dev/null 2>&1; then
    info "${MANAGER} started"
  else
    info "${MANAGER} did not start:"
    journalctl -u "${MANAGER}" --since "@${ts}" --no-pager 2>/dev/null |
      grep -E 'MISSING|INVALID|Unresolved|ERROR' | tail -n 5 | sed 's/^/  [INFO]   /' || true
  fi
}

# Installs the dashboard. It must reuse a shared CA that has its key, and mint one otherwise.
DASHBOARD_CA_EXPECTED=""
dashboard_install() {
  step "Install ${NAME}"
  if [ -f "${CA_DIR}/root-ca.pem" ] && [ -f "${CA_DIR}/root-ca.key" ]; then
    DASHBOARD_CA_EXPECTED="reusing the shared root CA"
  else
    DASHBOARD_CA_EXPECTED="created the shared root CA"
  fi
  install_ok "${DASHBOARD_PKG}"
  check "the install log says: ${DASHBOARD_CA_EXPECTED}" \
    contains "$(cat "${WORK}/install.out")" "${DASHBOARD_CA_EXPECTED}"
  check "certs/root-ca.pem is the shared CA" same_file "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/root-ca.pem"
  systemctl enable "${NAME}" >/dev/null 2>&1 || true
}

# expect_dashboard <label>: the pre-start verdict and the start outcome must match what
# credentials.env holds at this moment.
expect_dashboard() {
  local label="$1" key missing=""
  step "Dashboard ${label}"
  for key in WAZUH_INDEXER_KIBANASERVER_PASSWORD WAZUH_MANAGER_WUI_PASSWORD; do
    if has_key "${key}"; then
      info "${key} is in credentials.env: expected resolved"
    else
      info "${key} is not in credentials.env: expected MISSING"
      missing="${missing} ${key}"
    fi
  done
  prestart
  check_not "no INVALID key" contains "${PRE_OUT}" "INVALID "
  check_not "credentials file not REFUSED" contains "${PRE_OUT}" "REFUSED "
  for key in WAZUH_INDEXER_KIBANASERVER_PASSWORD WAZUH_MANAGER_WUI_PASSWORD; do
    case " ${missing} " in
      *" ${key} "*) check "reports MISSING ${key}" contains "${PRE_OUT}" "MISSING ${key}" ;;
      *) check_not "does not report MISSING ${key}" contains "${PRE_OUT}" "MISSING ${key}" ;;
    esac
  done
  case " ${missing} " in
    *" WAZUH_MANAGER_WUI_PASSWORD "*) ;;
    *) check "wazuh_core.hosts.default.password is in the keystore" ks_has wazuh_core.hosts.default.password ;;
  esac
  case " ${missing} " in
    *" WAZUH_INDEXER_KIBANASERVER_PASSWORD "*) ;;
    *) check "opensearch.password is in the keystore" ks_has opensearch.password ;;
  esac
  if [ -z "${missing}" ]; then
    check "prestart exits 0" prestart_rc_is 0
    check "systemctl start succeeds" svc_start
    check_running
  else
    check "prestart exits 1" prestart_rc_is 1
    check "systemctl start is refused" svc_start_refused
  fi
}

# [INFO] only: which CA each component trusts, whether the dashboard can reach the indexer, and
# the state of the three services.
full_info() {
  step "Setup state"
  local f conn
  for f in "${MANAGER_CA}" "${INDEXER_CA}"; do
    if [ ! -f "${f}" ]; then
      info "${f}: absent"
    elif same_file "${CA_DIR}/root-ca.pem" "${f}"; then
      info "${f}: the shared CA"
    else
      info "${f}: NOT the shared CA"
    fi
  done
  if curl -s -o /dev/null --cacert "${CERTS_DIR}/root-ca.pem" https://127.0.0.1:9200 2>/dev/null; then
    info "the indexer's TLS verifies against the dashboard's root-ca.pem"
  else
    info "the indexer's TLS does NOT verify against the dashboard's root-ca.pem (or it is down)"
  fi
  conn=$(journal_since "${CASE_STARTED}" | grep -cE 'ConnectionError|self.signed|unable to verify|certificate' || true)
  info "dashboard journal lines about the indexer connection or certificates: ${conn:-0}"
  for f in "${INDEXER}" "${MANAGER}" "${NAME}"; do
    info "${f}: $(systemctl is-active "${f}" 2>/dev/null)"
  done
}

# The kibanaserver password the indexer ships with, set the way an operator would when the indexer
# did not publish it.
readonly INDEXER_DEFAULT_KIBANA_PASS="kibanaserver"

# run_order "<I|M|D> <I|M|D> <I|M|D>": installs the three in that order and checks the dashboard
# after every step once it is installed; then supplies what is still missing as an operator would
# and checks that the dashboard runs.
run_order() {
  local pkg installed_d=0 after=""
  for pkg in $1; do
    case "${pkg}" in
      I) indexer_up; after="${after:+${after}, }indexer" ;;
      M) manager_up; after="${after:+${after}, }manager" ;;
      D) dashboard_install; installed_d=1; after="${after:+${after}, }dashboard" ;;
    esac
    if [ "${installed_d}" -eq 1 ]; then expect_dashboard "after installing: ${after}"; fi
  done

  step "Certificates"
  check "certs/root-ca.pem is the shared CA" same_file "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/root-ca.pem"
  check "dashboard.pem chains to the shared CA" \
    openssl verify -purpose sslserver -CAfile "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/dashboard.pem"
  if [ -f "${MANAGER_CA}" ]; then
    check "the manager's root-ca.pem is the same shared CA" same_file "${CA_DIR}/root-ca.pem" "${MANAGER_CA}"
  else
    info "the manager has no ${MANAGER_CA}"
  fi

  if ! has_key WAZUH_INDEXER_KIBANASERVER_PASSWORD; then
    step "Operator supplies WAZUH_INDEXER_KIBANASERVER_PASSWORD (the indexer's default)"
    printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\n' "${INDEXER_DEFAULT_KIBANA_PASS}" >>"${CREDENTIALS_FILE}"
  fi
  if ! has_key WAZUH_MANAGER_WUI_PASSWORD; then
    step "Operator supplies WAZUH_MANAGER_WUI_PASSWORD"
    printf 'WAZUH_MANAGER_WUI_PASSWORD=%s\n' "${WUI_PASS}" >>"${CREDENTIALS_FILE}"
  fi
  expect_dashboard "with every credential available"
  full_info
}

case_order_imd() { run_order "I M D"; }
case_order_idm() { run_order "I D M"; }
case_order_mid() { run_order "M I D"; }
case_order_mdi() { run_order "M D I"; }
case_order_dim() { run_order "D I M"; }
case_order_dmi() { run_order "D M I"; }

# Installs the three without starting the siblings: removal and reinstall only need their files.
install_all_quiet() {
  step "Install ${INDEXER}, ${MANAGER} and ${NAME} (not started)"
  check "${INDEXER} installs" sib_install "${INDEXER_PKG}" "${INDEXER}"
  check "${MANAGER} installs" sib_install "${MANAGER_PKG}" "${MANAGER}"
  dashboard_install
}

case_full_remove() {
  install_all_quiet
  local ca_fp wui_before=0
  ca_fp=$(fingerprint "${CA_DIR}/root-ca.pem")
  if has_key WAZUH_MANAGER_WUI_PASSWORD; then wui_before=1; fi
  info "WAZUH_MANAGER_WUI_PASSWORD in credentials.env before the purge: ${wui_before}"
  step "Purge ${NAME}, the manager and the indexer still installed"
  check "${NAME} purge succeeds" pkg_remove
  check_not "${NAME} no longer registered" pkg_present
  check "${WAZUH_DIR} kept" test -d "${WAZUH_DIR}"
  check "credentials.env kept" test -f "${CREDENTIALS_FILE}"
  check "shared CA kept" test "$(fingerprint "${CA_DIR}/root-ca.pem")" = "${ca_fp}"
  check "shared CA key kept" test -f "${CA_DIR}/root-ca.key"
  if [ "${wui_before}" -eq 1 ]; then
    check "the manager's WAZUH_MANAGER_WUI_PASSWORD kept" has_key WAZUH_MANAGER_WUI_PASSWORD
  fi

  step "Purge the manager, then the indexer ([INFO]: last-package-out across the three)"
  pkgname_remove "${MANAGER}" >/dev/null 2>&1 || info "${MANAGER} purge failed"
  if absent "${WAZUH_DIR}"; then
    info "after the manager purge: ${WAZUH_DIR} absent"
  else
    info "after the manager purge, left in ${WAZUH_DIR}: $(ls -A "${WAZUH_DIR}" | tr '\n' ' ')"
  fi
  pkgname_remove "${INDEXER}" >/dev/null 2>&1 || info "${INDEXER} purge failed"
  if absent "${WAZUH_DIR}"; then
    info "after the indexer purge: ${WAZUH_DIR} absent"
  else
    info "after the indexer purge, left in ${WAZUH_DIR}: $(ls -A "${WAZUH_DIR}" | tr '\n' ' ')"
  fi
}

case_full_reinstall() {
  install_all_quiet
  local ca_fp
  ca_fp=$(fingerprint "${CA_DIR}/root-ca.pem")
  step "Purge and reinstall ${NAME}"
  check "${NAME} purge succeeds" pkg_remove
  dashboard_install
  check "the reinstall reused the shared root CA" \
    contains "$(cat "${WORK}/install.out")" "reusing the shared root CA"
  check "shared CA unchanged" test "$(fingerprint "${CA_DIR}/root-ca.pem")" = "${ca_fp}"
  if has_key WAZUH_MANAGER_WUI_PASSWORD; then
    check "wazuh-wui resolved again from credentials.env" \
      contains "$(cat "${WORK}/install.out")" "stored wazuh_core.hosts.default.password in the keystore from ${CREDENTIALS_FILE}"
  else
    info "the manager did not publish WAZUH_MANAGER_WUI_PASSWORD; nothing to resolve again"
  fi
}

# -----------------------------------------------------------------------------------------
# Runner
# -----------------------------------------------------------------------------------------

RESULTS=()
PASSED=0
FAILED=0
SKIPPED=0

is_selected() {
  [ -z "${SELECTED}" ] && return 0
  case ",${SELECTED}," in *",$1,"*) return 0 ;; esac
  return 1
}

record() {
  RESULTS+=("$1|$2|$3|$4")
  case "$3" in
    PASS) PASSED=$((PASSED + 1)) ;;
    SKIP) SKIPPED=$((SKIPPED + 1)) ;;
    *) FAILED=$((FAILED + 1)) ;;
  esac
  printf '%-4s %-52s %-11s %s\n' "$1" "$2" "$3" "$4"
}

run_case() {
  local id="$1" title="$2" fn="$3" needs="$4"
  local log="${LOG_DIR}/${id}.log" rc started elapsed result

  if [ "${needs}" = dashboard-previous ] && [ -z "${DASHBOARD_PREV_PKG}" ]; then
    echo "SKIP: needs --dashboard-previous" >"${log}"
    record "${id}" "${title}" SKIP "-"
    return
  fi

  # Scratch data stays on a local filesystem: modes and root ownership must survive, which they do
  # not on a shared folder such as /vagrant.
  WORK=$(mktemp -d "/var/tmp/vm-test-matrix-${id}.XXXXXX")
  chmod 0700 "${WORK}"
  export WORK
  started=${SECONDS}
  local started_epoch
  started_epoch=$(date +%s)
  CASE_STARTED=${started_epoch}
  {
    echo "### ${id} ${title}"
    echo "### $(date -u '+%Y-%m-%dT%H:%M:%SZ') dashboard=${DASHBOARD_PKG}${DASHBOARD_PREV_PKG:+ previous=${DASHBOARD_PREV_PKG}}"
    if [ "${needs}" = full ]; then echo "### manager=${MANAGER_PKG} indexer=${INDEXER_PKG}"; fi
  } >"${log}"

  if [ "${VERBOSE}" -eq 1 ]; then
    (set -e; "${fn}") 2>&1 | tee -a "${log}"
    rc=${PIPESTATUS[0]}
  else
    (set -e; "${fn}") >>"${log}" 2>&1
    rc=$?
  fi

  if [ "${rc}" -ne 0 ]; then
    {
      echo
      echo "### case aborted with status ${rc}; diagnostics"
      systemctl status "${NAME}" --no-pager 2>&1 | head -20
      if [ "${needs}" = full ]; then
        systemctl status "${MANAGER}" "${INDEXER}" --no-pager 2>&1 | grep -E '^[^ ] |Active:'
      fi
      journalctl -u "${NAME}" --since "@${started_epoch}" --no-pager 2>/dev/null |
        grep -v 'agentkeepalive:deprecated' | tail -120
      ls -la "${CERTS_DIR}" "${WAZUH_DIR}" "${CA_DIR}" 2>&1
    } >>"${log}"
  fi

  echo >>"${log}"
  echo "### cleanup" >>"${log}"
  local clean_rc=0
  clean_host >>"${log}" 2>&1 || clean_rc=$?
  rm -rf "${WORK}"

  elapsed="$((SECONDS - started))s"
  if [ "${rc}" -eq 0 ] && [ "${clean_rc}" -eq 0 ]; then
    result=PASS
  elif [ "${rc}" -eq 0 ]; then
    result="FAIL(dirty)"
  else
    result=FAIL
  fi
  echo "### result: ${result} (${elapsed})" >>"${log}"
  record "${id}" "${title}" "${result}" "${elapsed}"
  if [ "${result}" != PASS ]; then
    grep -m1 '\[FAIL\]' "${log}" | sed 's/^ */       /' || true
    echo "       log: ${log}"
  fi
}

list_cases() {
  local entry id title fn needs note
  printf '%-4s %-52s %s\n' ID CASE NEEDS
  for entry in "${CASES[@]}"; do
    IFS='|' read -r id title fn needs <<<"${entry}"
    case "${needs}" in
      dashboard) note="--dashboard" ;;
      dashboard-previous) note="--dashboard, --dashboard-previous" ;;
      *) note="--dashboard, --manager, --indexer" ;;
    esac
    printf '%-4s %-52s %s\n' "${id}" "${title}" "${note}"
  done
}

usage() {
  sed -n '/^# Usage:/,/^# Exit status/p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "vm-test-matrix: $*" >&2
  exit 2
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dashboard) DASHBOARD_PKG="${2-}"; shift 2 ;;
      --dashboard-previous) DASHBOARD_PREV_PKG="${2-}"; shift 2 ;;
      --manager) MANAGER_PKG="${2-}"; shift 2 ;;
      --indexer) INDEXER_PKG="${2-}"; shift 2 ;;
      --cases) SELECTED="${2-}"; shift 2 ;;
      --list) LIST_ONLY=1; shift ;;
      --clean-only) CLEAN_ONLY=1; shift ;;
      --log-dir) LOG_DIR="${2-}"; shift 2 ;;
      --start-timeout) START_TIMEOUT="${2-}"; shift 2 ;;
      --skip-tls) SKIP_TLS=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      --force) FORCE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
  done
}

family_of() {
  case "$1" in
    *.deb) echo deb ;;
    *.rpm) echo rpm ;;
    *) echo "" ;;
  esac
}

# dpkg first: a Debian-based host can have rpm installed as well.
detect_family() {
  if command -v dpkg-query >/dev/null 2>&1; then echo deb
  elif command -v rpm >/dev/null 2>&1; then echo rpm
  fi
}

# Checks shared by test runs and --clean-only. FAMILY must be set.
preflight_host() {
  [ "$(id -u)" = 0 ] || die "must run as root"
  local tool
  case "${FAMILY}" in
    deb) for tool in dpkg dpkg-query dpkg-deb apt-get; do
           command -v "${tool}" >/dev/null 2>&1 || die "${tool} not found: is this a Debian-based host?"
         done ;;
    rpm) command -v rpm >/dev/null 2>&1 || die "rpm not found: is this an RPM-based host?" ;;
  esac
  for tool in systemctl journalctl openssl runuser sha256sum timeout awk sed flock; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} not found"
  done
  [ "$(cat /proc/1/comm 2>/dev/null)" = systemd ] || die "PID 1 is not systemd"

  if sibling_installed && [ "${SIBLINGS_MANAGED}" -ne 1 ]; then
    die "wazuh-indexer or wazuh-manager is installed but --manager/--indexer were not given; cleaning wipes ${WAZUH_DIR}. Use --force on a throwaway host"
  fi
}

preflight() {
  [ -n "${DASHBOARD_PKG}" ] || die "--dashboard is required"
  [ -f "${DASHBOARD_PKG}" ] || die "dashboard package not found: ${DASHBOARD_PKG}"
  DASHBOARD_PKG=$(readlink -f "${DASHBOARD_PKG}")
  FAMILY=$(family_of "${DASHBOARD_PKG}")
  [ -n "${FAMILY}" ] || die "cannot tell the package family from ${DASHBOARD_PKG} (.deb or .rpm)"
  if [ -n "${DASHBOARD_PREV_PKG}" ]; then
    [ -f "${DASHBOARD_PREV_PKG}" ] || die "previous dashboard package not found: ${DASHBOARD_PREV_PKG}"
    DASHBOARD_PREV_PKG=$(readlink -f "${DASHBOARD_PREV_PKG}")
    [ "$(family_of "${DASHBOARD_PREV_PKG}")" = "${FAMILY}" ] || die "--dashboard-previous must be a .${FAMILY} package"
  fi
  if [ -n "${MANAGER_PKG}${INDEXER_PKG}" ]; then
    [ -n "${MANAGER_PKG}" ] && [ -n "${INDEXER_PKG}" ] ||
      die "--manager and --indexer go together: the FULL cases need both"
    [ -f "${MANAGER_PKG}" ] || die "manager package not found: ${MANAGER_PKG}"
    [ -f "${INDEXER_PKG}" ] || die "indexer package not found: ${INDEXER_PKG}"
    MANAGER_PKG=$(readlink -f "${MANAGER_PKG}")
    INDEXER_PKG=$(readlink -f "${INDEXER_PKG}")
    [ "$(family_of "${MANAGER_PKG}")" = "${FAMILY}" ] || die "--manager must be a .${FAMILY} package"
    [ "$(family_of "${INDEXER_PKG}")" = "${FAMILY}" ] || die "--indexer must be a .${FAMILY} package"
    command -v curl >/dev/null 2>&1 || die "curl not found (needed by the FULL cases)"
  fi
  [[ "${START_TIMEOUT}" =~ ^[0-9]+$ ]] || die "--start-timeout must be a number of seconds"
  if [ -n "${SELECTED}" ]; then
    local id known entry
    for id in ${SELECTED//,/ }; do
      known=0
      for entry in "${CASES[@]}"; do [ "${entry%%|*}" = "${id}" ] && known=1; done
      [ "${known}" = 1 ] || die "unknown case: ${id} (see --list)"
      case "${id}" in
        F*) [ -n "${MANAGER_PKG}" ] || die "${id} is a FULL case: it needs --manager and --indexer" ;;
      esac
    done
  fi

  preflight_host
  command -v setcap >/dev/null 2>&1 ||
    echo "vm-test-matrix: warning: setcap not found (libcap2-bin / libcap); the install may fail" >&2

  local fstype
  fstype=$(stat -f -c '%T' "${LOG_DIR:-$(pwd)}" 2>/dev/null || echo unknown)
  case "${fstype}" in
    vboxsf|v9fs|9p|nfs*|fuse*|smb*|cifs)
      echo "vm-test-matrix: note: logs go to a ${fstype} mount; scratch data is kept in /var/tmp" >&2 ;;
  esac

}

print_summary() {
  local summary="${LOG_DIR}/summary.txt" entry id title result elapsed os
  os=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME}")
  {
    echo "wazuh-dashboard package test matrix"
    echo "Date:     $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Host:     $(hostname) - ${os:-unknown} ($(uname -m)), family ${FAMILY}"
    echo "Dashboard: $(basename "${DASHBOARD_PKG}") ($(pkg_file_version "${DASHBOARD_PKG}"))"
    [ -n "${DASHBOARD_PREV_PKG}" ] && echo "Previous:  $(basename "${DASHBOARD_PREV_PKG}") ($(pkg_file_version "${DASHBOARD_PREV_PKG}"))"
    [ -n "${MANAGER_PKG}" ] && echo "Manager:   $(basename "${MANAGER_PKG}") ($(pkg_file_version "${MANAGER_PKG}"))"
    [ -n "${INDEXER_PKG}" ] && echo "Indexer:   $(basename "${INDEXER_PKG}") ($(pkg_file_version "${INDEXER_PKG}"))"
    [ -z "${MANAGER_PKG}" ] && echo "FULL cases not run: --manager and --indexer not given"
    echo
    printf '%-4s %-52s %-11s %s\n' ID CASE RESULT TIME
    printf '%s\n' "--------------------------------------------------------------------------------"
    for entry in "${RESULTS[@]}"; do
      IFS='|' read -r id title result elapsed <<<"${entry}"
      printf '%-4s %-52s %-11s %s\n' "${id}" "${title}" "${result}" "${elapsed}"
    done
    printf '%s\n' "--------------------------------------------------------------------------------"
    echo "Total: ${#RESULTS[@]}  Passed: ${PASSED}  Failed: ${FAILED}  Skipped: ${SKIPPED}"
    echo "Logs:  ${LOG_DIR}"
  } >"${summary}"
  echo
  cat "${summary}"
}

# Two runs on one host install and purge the same package under each other, and a cleanup must not
# run under a matrix either.
take_lock() {
  exec 9>/run/vm-test-matrix.lock
  flock -n 9 || die "another vm-test-matrix run is in progress on this host"
}

main() {
  parse_args "$@"
  if [ "${LIST_ONLY}" -eq 1 ]; then
    list_cases
    exit 0
  fi
  if [ -n "${MANAGER_PKG}${INDEXER_PKG}" ] || [ "${FORCE}" -eq 1 ]; then
    SIBLINGS_MANAGED=1
  fi
  if [ "${CLEAN_ONLY}" -eq 1 ]; then
    local given
    given=$(printf '%s\n' "${DASHBOARD_PKG}" "${MANAGER_PKG}" "${INDEXER_PKG}" | grep -m1 . || true)
    if [ -n "${given}" ]; then
      FAMILY=$(family_of "${given}")
      [ -n "${FAMILY}" ] || die "cannot tell the package family from ${given} (.deb or .rpm)"
    else
      FAMILY=$(detect_family)
      [ -n "${FAMILY}" ] || die "neither dpkg nor rpm found: cannot tell the package family of this host"
    fi
    preflight_host
    take_lock
    echo "Cleaning the host (family ${FAMILY}$([ "${SIBLINGS_MANAGED}" -eq 1 ] && echo ', with wazuh-manager and wazuh-indexer'))"
    if clean_host; then
      echo "Host clean"
      exit 0
    fi
    echo "Host NOT clean"
    exit 1
  fi

  preflight
  take_lock

  LOG_DIR="${LOG_DIR:-$(pwd)/vm-test-results-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "${LOG_DIR}" || die "cannot create ${LOG_DIR}"
  LOG_DIR=$(readlink -f "${LOG_DIR}")

  echo "Cleaning the host before the first case"
  clean_host >"${LOG_DIR}/initial-cleanup.log" 2>&1 ||
    die "the host could not be cleaned; see ${LOG_DIR}/initial-cleanup.log"

  echo
  printf '%-4s %-52s %-11s %s\n' ID CASE RESULT TIME
  local entry id title fn needs full_left=0
  for entry in "${CASES[@]}"; do
    IFS='|' read -r id title fn needs <<<"${entry}"
    is_selected "${id}" || continue
    if [ "${needs}" = full ] && [ -z "${MANAGER_PKG}" ]; then
      full_left=$((full_left + 1))
      continue
    fi
    run_case "${id}" "${title}" "${fn}" "${needs}"
  done
  if [ "${full_left}" -gt 0 ]; then echo "FULL cases not run: --manager and --indexer not given"; fi

  print_summary
  [ "${FAILED}" -eq 0 ]
}

main "$@"
