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
# THE HOST IS WIPED AFTER EVERY CASE: the package is purged and /etc/wazuh-dashboard,
# /usr/share/wazuh-dashboard, /etc/wazuh (shared credentials file and CA) and the wazuh-dashboard
# user are removed. Run it only on a throwaway VM.
#
# Usage:
#   sudo ./vm-test-matrix.sh --package <wazuh-dashboard.deb|.rpm> [options]
#   sudo ./vm-test-matrix.sh --clean-only [--package <file>] [--force]
#
# Options:
#   --package <file>      Package under test (required unless --list or --clean-only).
#   --previous <file>     Older 5.x package of the same family; enables the upgrade cases.
#   --cases <ids>         Comma-separated case IDs to run (default: all), e.g. C01,C03.
#   --list                List the cases and exit.
#   --clean-only          Only wipe the host (the same cleanup every case ends with) and exit; no
#                         case runs. The family is taken from --package when given, else from the
#                         host's package manager.
#   --log-dir <dir>       Where per-case logs and the summary go (default: ./vm-test-results-<ts>).
#   --start-timeout <s>   Seconds to wait for the service to become active / serve TLS (default 180).
#   --skip-tls            Do not check that the dashboard serves its certificate over HTTPS.
#   --verbose             Also print each case's log to the console.
#   --force               Run even when wazuh-indexer or wazuh-manager is installed (they will
#                         lose /etc/wazuh).
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

PACKAGE=""
PREVIOUS=""
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
# Case registry: ID | title | function | needs --previous
# -----------------------------------------------------------------------------------------

CASES=(
  "C01|Fresh install on an empty host|case_fresh_install|0"
  "C02|Start without credentials is refused|case_start_without_credentials|0"
  "C03|Credentials in credentials.env before install|case_credentials_before_install|0"
  "C04|Credentials added after install|case_credentials_after_install|0"
  "C05|Credentials from the unit environment (aliases)|case_credentials_env_aliases|0"
  "C06|Environment wins over credentials.env|case_env_beats_file|0"
  "C07|Values the keystore would not store verbatim|case_invalid_values|0"
  "C08|Refused credentials file (bad mode)|case_refused_credentials_file|0"
  "C09|Keystore wins over credentials.env on restart|case_keystore_wins|0"
  "C10|Password configured in opensearch_dashboards.yml|case_yml_password|0"
  "C11|Existing shared CA with key is reused|case_existing_ca|0"
  "C12|Anchor-only shared CA|case_anchor_only_ca|0"
  "C13|Operator-supplied certificate pair is kept|case_operator_pair|0"
  "C14|Partial certificate pair is refused|case_partial_pair|0"
  "C15|Custom SANs and node name|case_custom_sans|0"
  "C16|resolve-credentials --clear|case_clear|0"
  "C17|Package removal / purge cleans the host|case_remove|0"
  "C18|Reinstall after removal mints a new CA|case_reinstall|0"
  "C19|Upgrade while running|case_upgrade_running|1"
  "C20|Upgrade while stopped|case_upgrade_stopped|1"
  "C21|No wazuh_core default host: wazuh-wui not needed|case_no_wazuh_host|0"
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

clean_host() {
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
  install_ok "${PACKAGE}"
  check "user ${NAME} exists" id "${NAME}"
  check "resolver is root:root 750" perm_is "${RESOLVER}" root:root:750
  check "shared library is root:root 640" perm_is "${INSTALL_DIR}/lib/wazuh-credentials.sh" root:root:640
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
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
  step "First start without credentials"
  check "systemctl start is refused" svc_start_refused
  step "The indexer and the manager publish their credentials later"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  check "systemctl start succeeds" svc_start
  check_running
  check "keystore holds every consumed entry" has_all_consumed_entries
}

case_credentials_env_aliases() {
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
  step "Valid values in the environment, an invalid one in credentials.env"
  write_creds "123456789e10" "${WUI_PASS}"
  printf 'WAZUH_INDEXER_KIBANASERVER_PASSWORD=%s\n' "${KIBANA_PASS}" >>"${ENV_FILE}"
  check "systemctl start succeeds (the environment wins)" svc_start
  check_running
  check "keystore holds every consumed entry" has_all_consumed_entries
}

case_invalid_values() {
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
  save_minted_ca
  local ca_fp
  ca_fp=$(fingerprint "${CA_DIR}/root-ca.pem")
  clean_host
  restore_ca root-ca.pem root-ca.key

  step "Install with the shared CA already present"
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
  save_minted_ca
  clean_host
  restore_ca root-ca.pem

  step "Install with an anchor-only shared CA"
  check "package installs despite the missing CA key" pkg_install "${PACKAGE}"
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
  install_ok "${PACKAGE}"
  check "install keeps the existing pair" \
    contains "$(cat "${WORK}/install.out")" "already holds a certificate pair"
  check "dashboard.pem unchanged" test "$(sha "${CERTS_DIR}/dashboard.pem")" = "${cert_sha}"
  check "dashboard-key.pem unchanged" test "$(sha "${CERTS_DIR}/dashboard-key.pem")" = "${key_sha}"
  check "root-ca.pem unchanged" test "$(sha "${CERTS_DIR}/root-ca.pem")" = "${ca_sha}"
  check "no shared CA minted over operator material" absent "${CA_DIR}/root-ca.pem"
}

case_partial_pair() {
  step "Only dashboard.pem is staged before installing"
  stage_operator_certs cert-only
  check "package installs" pkg_install "${PACKAGE}"
  check "install refuses to complete the pair" \
    contains "$(cat "${WORK}/install.out")" "refusing to complete it"
  check "no dashboard-key.pem created" absent "${CERTS_DIR}/dashboard-key.pem"
  check "no shared CA minted" absent "${CA_DIR}/root-ca.pem"
}

case_custom_sans() {
  step "Install with WAZUH_DASHBOARD_CERT_SANS and WAZUH_DASHBOARD_NODE_NAME"
  export WAZUH_DASHBOARD_CERT_SANS="DNS:dash.test,IP:10.9.8.7"
  export WAZUH_DASHBOARD_NODE_NAME="dash-node"
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
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
  install_ok "${PACKAGE}"
  local ca_fp
  ca_fp=$(fingerprint "${CA_DIR}/root-ca.pem")
  step "Remove with the package's own scripts, then reinstall"
  check "package removal succeeds" pkg_remove
  check "${WAZUH_DIR} removed with the last component" absent "${WAZUH_DIR}"
  # rpm may leave config files behind (.rpmsave); a reinstall must start from its own defaults.
  [ "${FAMILY}" = rpm ] && rm -rf "${CONFIG_DIR}"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${PACKAGE}"
  check "a new shared CA was minted" test "$(fingerprint "${CA_DIR}/root-ca.pem")" != "${ca_fp}"
  check "dashboard.pem chains to the new CA" \
    openssl verify -purpose sslserver -CAfile "${CA_DIR}/root-ca.pem" "${CERTS_DIR}/dashboard.pem"
  check "systemctl start succeeds" svc_start
  check_running
}

# Installs --previous with credentials and makes sure it has certificates (an older 5.x build may
# not issue them), leaving it stopped.
install_previous() {
  step "Install the previous package ($(pkg_file_version "${PREVIOUS}"))"
  write_creds "${KIBANA_PASS}" "${WUI_PASS}"
  install_ok "${PREVIOUS}"
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
  expected=$(pkg_file_version "${PACKAGE}")
  step "Upgrade to ${expected} while running"
  check "upgrade succeeds" pkg_upgrade "${PACKAGE}"
  check "installed version is ${expected}" test "$(pkg_installed_version)" = "${expected}"
  check_running
  check "dashboard.pem unchanged by the upgrade" test "$(sha "${CERTS_DIR}/dashboard.pem")" = "${cert_sha}"
  check "dashboard-key.pem unchanged by the upgrade" test "$(sha "${CERTS_DIR}/dashboard-key.pem")" = "${key_sha}"
  check "keystore holds every consumed entry" has_all_consumed_entries
}

case_upgrade_stopped() {
  install_previous
  local expected
  expected=$(pkg_file_version "${PACKAGE}")
  step "Upgrade to ${expected} while stopped"
  check "upgrade succeeds" pkg_upgrade "${PACKAGE}"
  check "installed version is ${expected}" test "$(pkg_installed_version)" = "${expected}"
  sleep 5
  check_not "service was not started by the upgrade" systemctl is-active --quiet "${NAME}"
  check "systemctl start succeeds" svc_start
  check_running
}

case_no_wazuh_host() {
  install_ok "${PACKAGE}"
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
  local id="$1" title="$2" fn="$3" needs_previous="$4"
  local log="${LOG_DIR}/${id}.log" rc started elapsed result

  if [ "${needs_previous}" = 1 ] && [ -z "${PREVIOUS}" ]; then
    echo "SKIP: needs --previous" >"${log}"
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
  {
    echo "### ${id} ${title}"
    echo "### $(date -u '+%Y-%m-%dT%H:%M:%SZ') package=${PACKAGE}${PREVIOUS:+ previous=${PREVIOUS}}"
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
  local entry id title fn prev
  printf '%-4s %-52s %s\n' ID CASE NOTES
  for entry in "${CASES[@]}"; do
    IFS='|' read -r id title fn prev <<<"${entry}"
    printf '%-4s %-52s %s\n' "${id}" "${title}" "$([ "${prev}" = 1 ] && echo 'needs --previous')"
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
      --package) PACKAGE="${2-}"; shift 2 ;;
      --previous) PREVIOUS="${2-}"; shift 2 ;;
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

  if sibling_installed && [ "${FORCE}" -ne 1 ]; then
    die "wazuh-indexer or wazuh-manager is installed; cleaning wipes ${WAZUH_DIR}. Use --force on a throwaway host"
  fi
}

preflight() {
  [ -n "${PACKAGE}" ] || die "--package is required"
  [ -f "${PACKAGE}" ] || die "package not found: ${PACKAGE}"
  PACKAGE=$(readlink -f "${PACKAGE}")
  FAMILY=$(family_of "${PACKAGE}")
  [ -n "${FAMILY}" ] || die "cannot tell the package family from ${PACKAGE} (.deb or .rpm)"
  if [ -n "${PREVIOUS}" ]; then
    [ -f "${PREVIOUS}" ] || die "previous package not found: ${PREVIOUS}"
    PREVIOUS=$(readlink -f "${PREVIOUS}")
    [ "$(family_of "${PREVIOUS}")" = "${FAMILY}" ] || die "--previous must be a .${FAMILY} package"
  fi
  [[ "${START_TIMEOUT}" =~ ^[0-9]+$ ]] || die "--start-timeout must be a number of seconds"

  preflight_host
  command -v setcap >/dev/null 2>&1 ||
    echo "vm-test-matrix: warning: setcap not found (libcap2-bin / libcap); the install may fail" >&2

  local fstype
  fstype=$(stat -f -c '%T' "${LOG_DIR:-$(pwd)}" 2>/dev/null || echo unknown)
  case "${fstype}" in
    vboxsf|v9fs|9p|nfs*|fuse*|smb*|cifs)
      echo "vm-test-matrix: note: logs go to a ${fstype} mount; scratch data is kept in /var/tmp" >&2 ;;
  esac

  if [ -n "${SELECTED}" ]; then
    local id known entry
    for id in ${SELECTED//,/ }; do
      known=0
      for entry in "${CASES[@]}"; do [ "${entry%%|*}" = "${id}" ] && known=1; done
      [ "${known}" = 1 ] || die "unknown case: ${id} (see --list)"
    done
  fi
}

print_summary() {
  local summary="${LOG_DIR}/summary.txt" entry id title result elapsed os
  os=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME}")
  {
    echo "wazuh-dashboard package test matrix"
    echo "Date:     $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Host:     $(hostname) - ${os:-unknown} ($(uname -m)), family ${FAMILY}"
    echo "Package:  $(basename "${PACKAGE}") ($(pkg_file_version "${PACKAGE}"))"
    [ -n "${PREVIOUS}" ] && echo "Previous: $(basename "${PREVIOUS}") ($(pkg_file_version "${PREVIOUS}"))"
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
  if [ "${CLEAN_ONLY}" -eq 1 ]; then
    if [ -n "${PACKAGE}" ]; then
      FAMILY=$(family_of "${PACKAGE}")
      [ -n "${FAMILY}" ] || die "cannot tell the package family from ${PACKAGE} (.deb or .rpm)"
    else
      FAMILY=$(detect_family)
      [ -n "${FAMILY}" ] || die "neither dpkg nor rpm found: cannot tell the package family of this host"
    fi
    preflight_host
    take_lock
    echo "Cleaning the host (family ${FAMILY})"
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
  local entry id title fn prev
  for entry in "${CASES[@]}"; do
    IFS='|' read -r id title fn prev <<<"${entry}"
    is_selected "${id}" || continue
    run_case "${id}" "${title}" "${fn}" "${prev}"
  done

  print_summary
  [ "${FAILED}" -eq 0 ]
}

main "$@"
