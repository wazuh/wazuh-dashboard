#!/bin/sh

# Copyright (C) 2015, Wazuh Inc.
#
# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.
#
# The dashboard's half of the credential resolution ladder.
#
# The shared half -- the credentials file, its locking convention and password validation -- lives
# in wazuh-credentials.sh, which the manager, the indexer and the dashboard must agree on exactly.
# It is therefore NOT in this repository: it is owned by wazuh-installation-assistant and
# downloaded by base-builder.sh at package build time into lib/wazuh-credentials.sh.
#
# This file adds only what is specific to the dashboard, and that is little: the dashboard OWNS NO
# SHARED CREDENTIAL and CONSUMES TWO PASSWORDS, both into its keystore.
#
#   WAZUH_INDEXER_KIBANASERVER_PASSWORD  kibanaserver, owned by the indexer
#                                        -> opensearch.username (kibanaserver), opensearch.password
#   WAZUH_MANAGER_WUI_PASSWORD           wazuh-wui, owned by the manager
#                                        -> wazuh_core.hosts.default.password
#
# So it never generates a password and never publishes a key into the credentials file: inventing
# a value does not make the peer accept it, and a key has exactly one writer -- its owner. It is
# the only component that can end with every one of its credentials unresolved.
#
# The one secret it does own is local to it: wazuh_ai_assistant.encryptionKey, which the AI
# assistant encrypts the provider API keys it stores with. Nobody else reads it, so it is
# generated here, straight into the keystore, and never published. See its own section below.
#
# It also owns its TLS certificates, certs/dashboard.pem and dashboard-key.pem, which a fresh
# install issues from the shared CA -- minting that CA first when no component has yet -- together
# with the certs/root-ca.pem anchor. That is the one thing the dashboard writes outside its own
# files, and only through the shared library, under its lock. See its own section below.
#
# The same script runs at three moments, and the difference between them is the whole design:
#
#   --install    From a FRESH postinst / %post -- never from an upgrade. Stores what it can, and has
#                no opinion about whether the dashboard can run. Never fails: a maintainer script
#                that aborts leaves the package half-configured, breaks `apt install -f` and fails
#                image builds. Exits 0 whatever it could not resolve, and says nothing about it --
#                except the TLS certificates, which are issued at this moment and no other.
#
#   --upgrade    From postinst / %post when a previous version was already installed. Identical to
#                --install for the consumed passwords: once both keystore entries exist step 0 is
#                true for both, so the only values it can fill in are the ones this host never had,
#                and nothing that is already configured changes. It does NOT generate the AI
#                assistant key: an upgrade adds no secret the operator did not have. Nor does it
#                touch the certificates: a pair the operator replaced must not be re-examined.
#
#   --prestart   From the unit's ExecStartPre=+ and from the SysV init script's start. Runs the same
#                ladder again, not merely a check, so a dashboard installed before the indexer or
#                the manager picks up what became available since and configures itself. Exits
#                non-zero naming every key it could not resolve.
#
#   --clear      Removes every credential this dashboard stores, the AI assistant key and the
#                certificates included -- and the shared CA when it was minted on this host -- so
#                the next --install or --prestart resolves from nothing. Nothing in the product calls it: it exists for
#                an image that was built by installing the package, whose postinst therefore
#                resolved this host's credentials into the image layer. Every container started
#                from such an image would otherwise share them. Run it at the end of the
#                Dockerfile, or once from an entrypoint before the first start.
#
# A credential the operator configured in opensearch_dashboards.yml is theirs, and is resolved as
# far as this script is concerned. The keystore is merged over the yml when the dashboard starts
# (src/cli/serve/serve.js), so writing an entry would silently override it -- and writing
# opensearch.username=kibanaserver over a custom user would pair one account's name with another's
# password. The precedence is therefore: keystore entry > yml setting > environment >
# credentials.env. The yml check is its own section below and stays out of the ladder's functions.
#
# Validating at start rather than at install is deliberate: the answer changes between the two
# moments and only the answer at start matters. A dashboard installed first resolves nothing; by
# the time it is started the indexer and the manager have published their keys, and it resolves.
# Checking at install would have declared a problem that no longer exists.
#
# The step never opens a network connection. It validates presence and format only -- making a
# service's start depend on reaching its peer would break boot ordering and cluster restarts.
# A credential that is present but wrong still fails as a 401 at runtime, exactly as today.

MODE="prestart"
DIR=""

# ${1-} rather than $1, matching the helpers' convention: the bare form is an "unbound variable"
# error under a caller that runs us with `set -u`, and `shift 2` on a lone -H is a hard error in
# dash rather than a diagnosable one.
while [ -n "${1-}" ]; do
    case "${1-}" in
        --install)  MODE="install" ; shift ;;
        --upgrade)  MODE="upgrade" ; shift ;;
        --prestart) MODE="prestart"; shift ;;
        --clear)    MODE="clear"   ; shift ;;
        -H)
            if [ -z "${2-}" ]; then
                echo "resolve-credentials: -H needs a directory" >&2
                exit 2
            fi
            DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--install|--upgrade|--prestart|--clear] [-H <home>]"
            exit 0
            ;;
        *)
            echo "resolve-credentials: unknown option: ${1-}" >&2
            exit 2
            ;;
    esac
done

# Derive the installation directory from our own location (bin/resolve-credentials), so a tree
# installed elsewhere resolves against itself rather than against a compiled-in path.
if [ -z "${DIR}" ]; then
    _self=$(readlink -f "$0" 2>/dev/null || echo "$0")
    DIR=$(dirname "$(dirname "${_self}")")
fi

# wazuh-credentials.sh is shared with the indexer and the manager, so it is owned by
# wazuh-installation-assistant and downloaded at build time -- it is NOT in this repository.
# WAZUH_SHARED_HELPER_DIR overrides where to look for it, which is what lets a test drive the
# ladder from the source tree; on an installed dashboard the lib/ branch wins.
_self_dir=$(dirname "$0")

if [ -n "${WAZUH_SHARED_HELPER_DIR-}" ] && [ -f "${WAZUH_SHARED_HELPER_DIR}/wazuh-credentials.sh" ]; then
    SHARED_HELPER_DIR="${WAZUH_SHARED_HELPER_DIR}"
elif [ -f "${DIR}/lib/wazuh-credentials.sh" ]; then
    SHARED_HELPER_DIR="${DIR}/lib"
elif [ -f "${_self_dir}/wazuh-credentials.sh" ]; then
    SHARED_HELPER_DIR="${_self_dir}"
else
    echo "resolve-credentials: cannot find wazuh-credentials.sh" >&2
    echo "        it is downloaded from wazuh-installation-assistant when the package is built" >&2
    exit 2
fi

. "${SHARED_HELPER_DIR}/wazuh-credentials.sh"

SERVICE_USER="wazuh-dashboard"
KEYSTORE_BIN="${DIR}/bin/opensearch-dashboards-keystore"
# The packaged keystore binary has OSD_PATH_CONF=/etc/wazuh-dashboard baked in, so this is where
# it reads and writes whatever our environment says.
CONFIG_DIR="${OSD_PATH_CONF:-/etc/wazuh-dashboard}"
KEYSTORE_FILE="${CONFIG_DIR}/opensearch_dashboards.keystore"
CONFIG_FILE="${CONFIG_DIR}/opensearch_dashboards.yml"
NODE_BIN="${DIR}/node/bin/node"
PID_FILE="/run/wazuh-dashboard/wazuh-dashboard.pid"

# Every keystore entry this script may write, and so every one --clear removes: the consumed
# credentials, and the one secret the dashboard owns.
LADDER_ENTRIES="opensearch.username opensearch.password wazuh_core.hosts.default.password"
OWNED_ENTRIES="wazuh_ai_assistant.encryptionKey"

LOG_TAG="resolve-credentials"

log() {
    echo "${LOG_TAG}: $*"
}

err() {
    echo "${LOG_TAG}: $*" >&2
}

# Accumulated verdicts. A key is *unresolved* when nothing supplied it and we may not invent it;
# it is *invalid* when something supplied it and the value failed the policy. The two are reported
# differently because they need different fixes, but both block the start.
UNRESOLVED=""
INVALID=""

# Set when the credentials file exists but was refused (ownership, mode, symlink, a bad ancestor,
# a malformed line), so the report can say that the value may well be there -- and why it was not
# read -- instead of only asking for it to be set.
CREDENTIALS_FILE_REFUSED=0

mark_unresolved() {
    UNRESOLVED="${UNRESOLVED} $1"
}

mark_invalid() {
    INVALID="${INVALID} $1"
}

# -----------------------------------------------------------------------------------------
# Keystore
#
# The keystore is created and read by the service user, and this script runs as root from
# postinst and from ExecStartPre=+. Every call therefore goes through runuser: a keystore written
# by root is a keystore the service can no longer read.
#
# Secrets reach it through stdin (`add <key> --stdin`), never argv, and never interpolated into a
# `runuser --command="..."` string: either one is a secret in ps for as long as the process lives.
# The working directory is / so the service user never has to traverse root's.
# -----------------------------------------------------------------------------------------

keystore() {
    if [ "$(id -u)" = 0 ]; then
        (cd / && runuser -u "${SERVICE_USER}" -- "${KEYSTORE_BIN}" "$@")
    else
        (cd / && "${KEYSTORE_BIN}" "$@")
    fi
}

# Cached, because every call starts Node: one listing per run, updated as we add.
KEYSTORE_KEYS=""
KEYSTORE_READY=0

keystore_load() {
    KEYSTORE_KEYS=$(keystore list </dev/null 2>/dev/null) || KEYSTORE_KEYS=""
}

keystore_has() {
    printf '%s\n' "${KEYSTORE_KEYS}" | grep -qxF -- "$1"
}

# postinst creates the keystore before it calls us, but --clear leaves a host that may reach
# --prestart without one, and so does a tree an operator tidied by hand. `create` on an existing
# keystore asks whether to overwrite it, so it only runs when the file is absent -- and with stdin
# closed, so a race with another writer answers "no" instead of hanging the start.
keystore_ensure() {
    if [ ! -x "${KEYSTORE_BIN}" ]; then
        err "cannot use the keystore: ${KEYSTORE_BIN} is missing"
        return 1
    fi
    if [ ! -f "${KEYSTORE_FILE}" ]; then
        keystore create </dev/null >/dev/null 2>&1
        if [ ! -f "${KEYSTORE_FILE}" ]; then
            err "could not create the keystore in ${KEYSTORE_FILE}"
            return 1
        fi
        log "created the keystore in ${KEYSTORE_FILE}"
    fi
    keystore_load
    return 0
}

# $1 is the entry; the value comes on our stdin and goes straight to the keystore's. It runs on
# the right of a pipe -- a subshell -- so the caller records the entry with keystore_mark().
keystore_add() {
    keystore add "$1" --stdin >/dev/null 2>&1
}

keystore_mark() {
    KEYSTORE_KEYS="${KEYSTORE_KEYS}
$1"
}

# -----------------------------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------------------------

# The process environment, then the credentials file. The environment wins because it is the more
# deliberate and more immediate input, and because an orchestrator setting a value should not be
# silently overridden by a file left behind from an earlier install.
#
# Within the environment the scoped name comes first and the wazuh-docker name after it. The
# aliases are environment-only: they are what the existing containers already set, and the file
# has never carried them.
#
# An explicitly empty value is treated as absent rather than as a policy failure: that is what an
# operator who cleared a variable means, and it leaves the key unresolved with a message rather
# than blocking the install on a validation error. The first name that is set decides, so a
# cleared scoped variable is not quietly overridden by an alias still lying around.
#
# Sets SETTING_VALUE and SETTING_SOURCE rather than printing, so the caller can say where a value
# came from without a second lookup. Returns 0 when set, 1 when absent, 2 when the file itself is
# unusable -- the library has then already said why.
SETTING_VALUE=""
SETTING_SOURCE=""

setting_get() {
    _sg_name="$1"
    _sg_alias="${2-}"
    SETTING_VALUE=""
    SETTING_SOURCE=""

    for _sg_env in "${_sg_name}" ${_sg_alias}; do
        if eval "[ \"\${${_sg_env}+x}\" = x ]"; then
            eval "_sg_value=\${${_sg_env}-}"
            [ -n "${_sg_value}" ] || return 1
            SETTING_VALUE="${_sg_value}"
            SETTING_SOURCE="the environment (${_sg_env})"
            return 0
        fi
    done

    _sg_status=0
    _sg_value=$(wazuh_env_get "${_sg_name}") || _sg_status=$?
    case "${_sg_status}" in
        0) [ -n "${_sg_value}" ] || return 1
           SETTING_VALUE="${_sg_value}"
           SETTING_SOURCE="$(wazuh_env_get_file 2>/dev/null || echo credentials.env)"
           return 0
           ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

# A supplied password may only use the generator's alphabet -- the owners generate from it, and
# anything else never logs in on the manager's side (connexion decodes Basic auth as latin1).
#
# The set is matched by `LC_ALL=C tr` rather than by a glob in the shell: ranges are
# locale-dependent, and the maintainer scripts inherit whatever locale the operator's session or
# the package manager happens to carry. `printf` is a builtin, so the value reaches `tr` over a
# pipe and never through a command line.
#
# The keystore adds one rule of its own: `add` runs JSON.parse on the value and stores whatever
# parses, so a password that happens to be a JSON number -- 123456789e10, 1e999999999999 -- would
# be stored as a number (or as Infinity) and sent as something else entirely. The alphabet leaves
# numbers as the only JSON that can get through; quotes and brackets are not in it.
#
# Every rejection names the rule, never the value.
password_is_valid() {
    _piv_rest=$(printf '%s' "$1" | LC_ALL=C tr -d 'A-Za-z0-9.,_+:@%^=~-') || return 1
    if [ -n "${_piv_rest}" ]; then
        err "the value contains characters outside A-Z a-z 0-9 . , _ + : @ % ^ = ~ -"
        return 1
    fi
    if printf '%s' "$1" | LC_ALL=C grep -Eqx -- '-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?'; then
        err "the value is a JSON number, which the keystore would not store as text"
        return 1
    fi
    wazuh_password_validate "$1"
}

# -----------------------------------------------------------------------------------------
# Consumed: kibanaserver and wazuh-wui
#
# Never generated, never published. Step 0 is the keystore entry itself: once it exists the
# credential is resolved, whatever the file now says -- a package must never reconfigure what is
# already configured, and that is also why the credentials file can be deleted once every component
# is installed and running.
#
#   resolve_consumed KEY ALIAS ENTRY [USERNAME_ENTRY USERNAME]
# -----------------------------------------------------------------------------------------

# A username the operator already stored is kept, so only an absent one gets the account name.
store_username() {
    [ -n "${1-}" ] || return 0
    keystore_has "$1" && return 0
    printf '%s' "$2" | keystore_add "$1" || return 1
    keystore_mark "$1"
}

resolve_consumed() {
    _rc_key="$1"
    _rc_alias="$2"
    _rc_entry="$3"
    _rc_user_entry="${4-}"
    _rc_user="${5-}"

    if [ "${KEYSTORE_READY}" -ne 1 ]; then
        mark_unresolved "${_rc_key}"
        return 1
    fi

    if keystore_has "${_rc_entry}"; then
        if ! store_username "${_rc_user_entry}" "${_rc_user}"; then
            err "could not write ${_rc_user_entry} to the keystore"
            mark_unresolved "${_rc_key}"
            return 1
        fi
        log "${_rc_entry} is already in the keystore; ${_rc_key} is ignored"
        return 0
    fi

    _rc_status=0
    setting_get "${_rc_key}" "${_rc_alias}" || _rc_status=$?

    if [ "${_rc_status}" -ne 0 ]; then
        [ "${_rc_status}" -eq 2 ] && CREDENTIALS_FILE_REFUSED=1
        mark_unresolved "${_rc_key}"
        return 1
    fi

    if ! password_is_valid "${SETTING_VALUE}"; then
        err "${_rc_key} from ${SETTING_SOURCE} was rejected by the password policy"
        mark_invalid "${_rc_key}"
        SETTING_VALUE=""
        return 1
    fi

    if ! store_username "${_rc_user_entry}" "${_rc_user}" ||
       ! printf '%s' "${SETTING_VALUE}" | keystore_add "${_rc_entry}"; then
        err "could not write ${_rc_entry} to the keystore"
        mark_unresolved "${_rc_key}"
        SETTING_VALUE=""
        return 1
    fi
    SETTING_VALUE=""
    keystore_mark "${_rc_entry}"

    log "stored ${_rc_entry} in the keystore from ${SETTING_SOURCE}"
    return 0
}

# -----------------------------------------------------------------------------------------
# The configuration file
#
# Deliberately separate from the ladder above: resolve_consumed() knows nothing about the yml, and
# these functions know nothing about the keystore. The run section combines them.
#
# The yml is read by the dashboard's own Node, through @osd/config's getConfigFromFiles() -- the
# same reader the dashboard uses, so flat (opensearch.password: x), nested and mixed keys and
# ${ENV} references mean here exactly what they mean at start. Where that module cannot be
# resolved, js-yaml (which it wraps) is used directly with a lookup that accepts both forms.
#
# It runs as the service user, which owns the file, and prints nothing: the answer is the exit
# status, never a value -- 0 set, 3 not set, 2 the file could not be read. Anything that goes
# wrong (no Node, an unreadable or unparseable file, an unknown ${ENV} reference) is 2, which every
# caller treats as "not set", so the ladder carries on as without the check; a broken yml is the
# dashboard's to report when it starts. Only a file that was read and lacks a setting is 3.
# -----------------------------------------------------------------------------------------

CONFIG_HAS_JS='
try {
  const [home, file, key] = process.argv.slice(1);
  let config;
  try {
    const { getConfigFromFiles } = require(require.resolve("@osd/config", { paths: [home] }));
    config = getConfigFromFiles([file]);
  } catch (e) {
    if (!e || e.code !== "MODULE_NOT_FOUND") throw e;
    const yaml = require(require.resolve("js-yaml", { paths: [home] }));
    config = yaml.load(require("fs").readFileSync(file, "utf8")) || {};
  }
  const lookup = (node, parts) => {
    if (parts.length === 0) return node;
    if (node === null || typeof node !== "object") return undefined;
    for (let i = parts.length; i > 0; i--) {
      const head = parts.slice(0, i).join(".");
      if (Object.prototype.hasOwnProperty.call(node, head)) {
        const found = lookup(node[head], parts.slice(i));
        if (found !== undefined) return found;
      }
    }
    return undefined;
  };
  const value = lookup(config, key.split("."));
  const set = (typeof value === "string" && value !== "") ||
    (value !== null && typeof value === "object" && Object.keys(value).length > 0);
  process.exit(set ? 0 : 3);
} catch (e) {
  process.exit(2);
}
'

config_has() {
    [ -x "${NODE_BIN}" ] && [ -f "${CONFIG_FILE}" ] || return 2
    _ch_status=0
    if [ "$(id -u)" = 0 ]; then
        (cd / && runuser -u "${SERVICE_USER}" -- \
            "${NODE_BIN}" -e "${CONFIG_HAS_JS}" "${DIR}" "${CONFIG_FILE}" "$1") \
            </dev/null >/dev/null 2>&1 || _ch_status=$?
    else
        (cd / && "${NODE_BIN}" -e "${CONFIG_HAS_JS}" "${DIR}" "${CONFIG_FILE}" "$1") \
            </dev/null >/dev/null 2>&1 || _ch_status=$?
    fi
    # runuser's own failures must not pass for "not set".
    case "${_ch_status}" in
        0|3) return "${_ch_status}" ;;
        *)   return 2 ;;
    esac
}

config_resolves_kibanaserver() {
    config_has opensearch.password || return 1
    log "opensearch.password is set in ${CONFIG_FILE}; WAZUH_INDEXER_KIBANASERVER_PASSWORD is not resolved"
}

# Without a `default` host there is nothing to authenticate, and an entry for it would create a
# host out of a lone password when the keystore is merged in.
config_resolves_wui() {
    _crw_status=0
    config_has wazuh_core.hosts.default || _crw_status=$?
    if [ "${_crw_status}" -eq 3 ]; then
        log "${CONFIG_FILE} defines no wazuh_core.hosts.default; WAZUH_MANAGER_WUI_PASSWORD is not needed"
        return 0
    fi
    config_has wazuh_core.hosts.default.password || return 1
    log "wazuh_core.hosts.default.password is set in ${CONFIG_FILE}; WAZUH_MANAGER_WUI_PASSWORD is not resolved"
}

# -----------------------------------------------------------------------------------------
# Owned: the AI assistant encryption key
#
# Deliberately separate from the ladder: it is not a credential anybody else holds, so it is never
# read from the environment or the credentials file, never validated against the password policy,
# and never published. The AI assistant is optional, so failing to generate it is a warning and
# never blocks the start -- the plugin itself says what is missing when it is used.
#
# Step 0 is the keystore entry or a value the operator configured in opensearch_dashboards.yml.
# Once either exists the key is never touched again: the provider API keys the assistant stored
# are encrypted with it, and a new key could no longer decrypt them.
#
# base64 of exactly 32 bytes is always 44 characters with one '=' pad, which also means it can
# never parse as a JSON number, so the keystore stores it as the string the plugin expects.
# -----------------------------------------------------------------------------------------

ENCRYPTION_KEY_ENTRY="wazuh_ai_assistant.encryptionKey"

encryption_key_generate() {
    _ekg_key=""
    if command -v openssl >/dev/null 2>&1; then
        _ekg_key=$(openssl rand -base64 32 2>/dev/null | tr -d '\n') || _ekg_key=""
    fi
    if [ -z "${_ekg_key}" ] && [ -r /dev/urandom ] && command -v base64 >/dev/null 2>&1; then
        _ekg_key=$(head -c 32 /dev/urandom | base64 | tr -d '\n') || _ekg_key=""
    fi
    if [ -z "${_ekg_key}" ] && [ -x "${NODE_BIN}" ]; then
        _ekg_key=$("${NODE_BIN}" -e \
            "process.stdout.write(require('crypto').randomBytes(32).toString('base64'))" 2>/dev/null) || _ekg_key=""
    fi
    [ "${#_ekg_key}" -eq 44 ] || return 1
    printf '%s' "${_ekg_key}"
}

resolve_encryption_key() {
    [ "${KEYSTORE_READY}" -eq 1 ] || return 1

    if keystore_has "${ENCRYPTION_KEY_ENTRY}"; then
        log "${ENCRYPTION_KEY_ENTRY} is already in the keystore"
        return 0
    fi
    if config_has "${ENCRYPTION_KEY_ENTRY}"; then
        log "${ENCRYPTION_KEY_ENTRY} is set in ${CONFIG_FILE}; not generated"
        return 0
    fi

    # Captured, then piped: the value is never on a command line, and never printed.
    if _rek_key=$(encryption_key_generate) &&
       printf '%s' "${_rek_key}" | keystore_add "${ENCRYPTION_KEY_ENTRY}"; then
        _rek_key=""
        keystore_mark "${ENCRYPTION_KEY_ENTRY}"
        log "generated ${ENCRYPTION_KEY_ENTRY}"
        return 0
    fi
    _rek_key=""
    err "warning: could not generate ${ENCRYPTION_KEY_ENTRY}; configure it manually to enable the AI assistant"
    return 1
}

# -----------------------------------------------------------------------------------------
# The credentials file
#
# The dashboard publishes nothing, but it may still be the first Wazuh package on the host. It
# then creates /etc/wazuh and an empty credentials.env, so a sibling installed later finds the file
# where it expects it and the operator has one obvious place to fill in. Creating it counts as a
# write, so it happens under the shared lock, through the library's own tree creation: 0700
# root:root directories, one component at a time, and nothing that already exists is repaired.
#
# The library's lock and tree helpers are private to it, but it is downloaded and pinned as one
# file, so the helpers used here cannot drift from the public functions that share the lock.
# -----------------------------------------------------------------------------------------

_credentials_file_create_locked() {
    _cfc_file=$(wazuh_env_get_file) || return 1
    if [ -e "${_cfc_file}" ] || [ -L "${_cfc_file}" ]; then
        _wazuh_validate_credentials_file
        return $?
    fi
    (umask 077; set -C; : >"${_cfc_file}") 2>/dev/null || {
        [ -e "${_cfc_file}" ] || return 1
    }
    chown root:root "${_cfc_file}" || return 1
    chmod 0600 "${_cfc_file}" || return 1
    _wazuh_restorecon "${_cfc_file}" || return 1
    _wazuh_validate_credentials_file
}

credentials_file_ensure() {
    [ "$(id -u)" = 0 ] || return 0
    _cfe_file=$(wazuh_env_get_file 2>/dev/null) || return 1
    [ -e "${_cfe_file}" ] && return 0
    if _wazuh_with_lock _credentials_file_create_locked; then
        log "created an empty ${_cfe_file}"
        return 0
    fi
    # Not fatal: an unusable file only means the keys it would have held stay unresolved, and
    # the library has already said which rule the path broke.
    return 1
}

# -----------------------------------------------------------------------------------------
# Owned: the dashboard's own certificates
#
# opensearch_dashboards.yml serves HTTPS from certs/dashboard.pem and dashboard-key.pem, and trusts
# the indexer through certs/root-ca.pem. On a fresh install, and only then, this issues whatever of
# that is missing from the shared CA, so every Wazuh component on the host chains to one anchor:
#
#   * No CA in the CA directory (/etc/wazuh/ca, or WAZUH_CA_DIR): the library mints one, and the
#     manager and the indexer installed after us issue from it too.
#   * A CA with its private key: reused, whoever minted it.
#   * An anchor without a key: a CA managed elsewhere. It can be trusted but not issued from, so a
#     missing pair is an error the operator fixes by staging one.
#
# An existing complete pair is how an operator supplies their own, so it is checked and never
# replaced. A partial pair is refused rather than completed: half of someone else's material is not
# ours to guess the other half of. And when the CA is gone but dashboard material is present, no
# new CA is minted -- it could only produce a pair that trusts a different anchor than the rest.
#
# Certificates are issued at install and never looked at again, for the same reasons as the
# manager's: resolving one is a signature, not a lookup, and it is the credential an operator
# legitimately rotates out of band. --upgrade and --prestart leave them alone; whether the dashboard
# accepts them is decided when it loads them.
#
# Placement: /etc/wazuh-dashboard belongs to the service user, who could swap certs/ or plant names
# in it while root issues. Everything therefore happens from inside the directory once it has been
# checked, in a root-only 0700 staging directory, and each file is published with `ln -T`, which
# neither follows nor replaces an existing name. The key goes before the certificate, so an
# interrupted run leaves a partial pair that the next run refuses, never a certificate without its
# key that looks complete. The result follows wazuh-certs-tool's layout: certs/ 0500 and files
# 0400, owned by the service user.
#
#   WAZUH_DASHBOARD_CERT_SANS   Exact comma-separated SAN list (DNS:name, IP:address, or untyped),
#                               environment then credentials.env. Default: the node name, the FQDN,
#                               every global-scope address, and loopback.
#   WAZUH_DASHBOARD_NODE_NAME   Certificate common name. Default: hostname -s.
# -----------------------------------------------------------------------------------------

CERTS_DIR="${CONFIG_DIR}/certs"
CERT_FILE="dashboard.pem"
CERT_KEY_FILE="dashboard-key.pem"
CERT_CA_FILE="root-ca.pem"

_dc_require() {
    for _dcr_function in wazuh_ca_get_dir _wazuh_ca_ensure_locked _wazuh_validate_ca_files \
        _wazuh_with_lock _wazuh_restorecon wazuh_env_get; do
        if ! command -v "${_dcr_function}" >/dev/null 2>&1; then
            err "the shared credentials library has no ${_dcr_function}; it is too old to issue certificates"
            return 1
        fi
    done
    for _dcr_command in awk chmod chown cmp flock ln mktemp openssl stat tr; do
        if ! command -v "${_dcr_command}" >/dev/null 2>&1; then
            err "cannot issue certificates without ${_dcr_command}"
            return 1
        fi
    done
}

_dc_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

_dc_valid_dns() {
    [ -n "$1" ] && [ "${#1}" -le 253 ] || return 1
    case "$1" in
        *[!A-Za-z0-9.*-]*|.*|*.|*..*|-*|*-) return 1 ;;
    esac
}

# Loose on purpose: the alphabet keeps the value from breaking out of the OpenSSL config line, and
# OpenSSL itself rejects a malformed address when it signs.
_dc_valid_ip() {
    case "$1" in
        ''|*[!0-9A-Fa-f.:]*) return 1 ;;
        *:*) return 0 ;;
    esac
    printf '%s\n' "$1" | LC_ALL=C grep -Eqx '([0-9]{1,3}\.){3}[0-9]{1,3}'
}

# One typed SAN per line from a comma-separated list; untyped entries are classified. The loop is
# the last command of its pipeline, so an invalid entry fails the capture rather than vanishing.
_dc_normalize_sans() {
    _dcn_typed=$(printf '%s' "$1" | tr ',' '\n' | while IFS= read -r _dcn_item || [ -n "${_dcn_item}" ]; do
        _dcn_item=$(printf '%s' "${_dcn_item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "${_dcn_item}" in
            '') continue ;;
            DNS:*|dns:*) _dcn_type=DNS; _dcn_value=${_dcn_item#*:} ;;
            IP:*|ip:*)   _dcn_type=IP;  _dcn_value=${_dcn_item#*:} ;;
            *:*)         _dcn_type=IP;  _dcn_value=${_dcn_item} ;;
            *)
                _dcn_value=${_dcn_item}
                if _dc_valid_ip "${_dcn_value}"; then _dcn_type=IP; else _dcn_type=DNS; fi
                ;;
        esac
        if [ "${_dcn_type}" = IP ]; then
            _dc_valid_ip "${_dcn_value}" || { err "invalid SAN entry: ${_dcn_item}"; exit 1; }
        else
            _dc_valid_dns "${_dcn_value}" || { err "invalid SAN entry: ${_dcn_item}"; exit 1; }
        fi
        printf '%s:%s\n' "${_dcn_type}" "${_dcn_value}"
    done) || return 1
    printf '%s\n' "${_dcn_typed}" | awk '
        NF == 0 { next }
        /^DNS:/ { key = "DNS:" tolower(substr($0, 5)) }
        /^IP:/  { key = tolower($0) }
        !seen[key]++ { print }
    '
}

_dc_node_name() {
    if [ -n "${WAZUH_DASHBOARD_NODE_NAME-}" ]; then
        _dcnn_node=${WAZUH_DASHBOARD_NODE_NAME}
    else
        _dcnn_node=$(hostname -s 2>/dev/null || uname -n 2>/dev/null) || _dcnn_node=""
        _dcnn_node=${_dcnn_node%%.*}
    fi
    if ! _dc_valid_dns "${_dcnn_node}"; then
        err "invalid dashboard node name: ${_dcnn_node}; set WAZUH_DASHBOARD_NODE_NAME"
        return 1
    fi
    printf '%s\n' "${_dcnn_node}"
}

# An explicit list replaces discovery; loopback is always added, since the dashboard is reached
# locally as well. Discovery never fails the issue: an address it misses is one the operator adds.
#
# The list goes to stdout, so where it came from is written to the file $2 for the caller to log:
# a log line here would end up in the list.
_dc_sans() {
    _dcs_status=0
    setting_get WAZUH_DASHBOARD_CERT_SANS || _dcs_status=$?
    case "${_dcs_status}" in
        0)
            _dcs_list="${SETTING_VALUE}"
            printf 'SANs set by WAZUH_DASHBOARD_CERT_SANS from %s\n' "${SETTING_SOURCE}" >"$2"
            ;;
        1)
            _dcs_list="DNS:$1"
            _dcs_fqdn=$(hostname -f 2>/dev/null || :)
            if [ -n "${_dcs_fqdn}" ] && _dc_valid_dns "${_dcs_fqdn}"; then
                _dcs_list="${_dcs_list},DNS:${_dcs_fqdn}"
            fi
            if command -v ip >/dev/null 2>&1; then
                _dcs_addrs=$(ip -o addr show 2>/dev/null | awk '
                    ($3 == "inet" || $3 == "inet6") && / scope global/ &&
                    !/ (tentative|dadfailed)( |$)/ { sub(/\/.*/, "", $4); printf ",IP:%s", $4 }
                ')
                _dcs_list="${_dcs_list}${_dcs_addrs}"
                _dcs_count=$(printf '%s' "${_dcs_addrs}" | tr ',' '\n' | grep -c '^IP:')
                printf 'SANs discovered: host name, FQDN and %s global address(es); set WAZUH_DASHBOARD_CERT_SANS to replace them\n' \
                    "${_dcs_count}" >"$2"
            else
                printf '%s\n' "SANs discovered without addresses (ip is not available): the certificate names only this host and loopback" >"$2"
            fi
            ;;
        *) err "cannot read WAZUH_DASHBOARD_CERT_SANS"; return 1 ;;
    esac
    SETTING_VALUE=""
    _dc_normalize_sans "${_dcs_list},DNS:localhost,IP:127.0.0.1,IP:::1"
}

# $1 config, $2 CN, $3 file with one typed SAN per line.
_dc_write_leaf_config() {
    {
        printf '%s\n' '[ req ]' 'prompt = no' 'default_md = sha256' 'distinguished_name = req_dn' ''
        printf '%s\n' '[ req_dn ]' 'C = US' 'L = California' 'O = Wazuh' 'OU = Wazuh'
        printf 'CN = %s\n\n' "$2"
        printf '%s\n' '[ v3_leaf ]' \
            'authorityKeyIdentifier = keyid,issuer' \
            'subjectKeyIdentifier = hash' \
            'basicConstraints = critical,CA:FALSE' \
            'keyUsage = critical,digitalSignature,keyEncipherment' \
            'extendedKeyUsage = serverAuth,clientAuth' \
            'subjectAltName = @alt_names' '' '[ alt_names ]'
        awk '
            /^IP:/  { ip++;  print "IP." ip " = " substr($0, 4) }
            /^DNS:/ { dns++; print "DNS." dns " = " substr($0, 5) }
        ' "$3"
    } >"$1"
}

# $1 certificate, $2 key, $3 CA to chain to (empty: no chain check). Prints nothing on success.
_dc_validate_pair() {
    if [ -L "$1" ] || [ ! -f "$1" ] || [ -L "$2" ] || [ ! -f "$2" ]; then
        err "the certificate pair must be two regular files: $1, $2"
        return 1
    fi
    if ! openssl x509 -in "$1" -noout -checkend 0 >/dev/null 2>&1; then
        err "invalid or expired certificate: $1"
        return 1
    fi
    _dcv_cert_pub=$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null) || return 1
    _dcv_key_pub=$(openssl pkey -in "$2" -passin pass: -pubout </dev/null 2>/dev/null) || {
        err "invalid private key: $2"
        return 1
    }
    if [ "${_dcv_cert_pub}" != "${_dcv_key_pub}" ]; then
        err "the private key does not match the certificate: $1"
        return 1
    fi
    if [ -n "${3-}" ] &&
       ! openssl verify -purpose sslserver -CAfile "$3" "$1" >/dev/null 2>&1; then
        err "the certificate does not chain to $3 for server use: $1"
        return 1
    fi
}

_dc_fingerprint() {
    openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null
}

# One line describing a certificate for the logs: subject, expiry and SHA-256 fingerprint. Public
# data only. Each field is picked by its label, since the order OpenSSL prints them in varies.
_dc_describe_cert() {
    _dcd_text=$(LC_ALL=C openssl x509 -in "$1" -noout -subject -enddate -fingerprint -sha256 2>/dev/null) || {
        printf '%s\n' "unreadable certificate"
        return 0
    }
    printf 'subject %s; valid until %s; SHA-256 %s\n' \
        "$(printf '%s\n' "${_dcd_text}" | sed -n 's/^subject= *//p' | head -n 1)" \
        "$(printf '%s\n' "${_dcd_text}" | sed -n 's/^notAfter=//p' | head -n 1)" \
        "$(printf '%s\n' "${_dcd_text}" | sed -n 's/^[Ss][Hh][Aa]256 Fingerprint=//p' | head -n 1)"
}

# Enters the child directory $1 of the working directory and proves it is one: its `..` must be the
# directory we came from. A name swapped for a symlink between the check and the cd lands
# somewhere else, whose `..` is not ours.
_dc_enter_child() {
    _dce_here=$(stat -c '%d:%i' . 2>/dev/null) || return 1
    if [ -L "$1" ] || [ ! -d "$1" ]; then
        err "refusing $1: it is not a real directory"
        return 1
    fi
    cd -P -- "$1" || return 1
    if [ "$(stat -c '%d:%i' .. 2>/dev/null)" != "${_dce_here}" ]; then
        err "$1 changed while certificates were being issued"
        return 1
    fi
}

# Enters the staging directory $1 of the certificates directory. Only root can have made a
# root-owned 0700 directory there, so passing this means the staging area is ours and no one else
# can reach into it.
_dc_enter_stage() {
    _dc_enter_child "$1" || return 1
    if [ "$(stat -c '%u:%a' . 2>/dev/null)" != "0:700" ]; then
        err "the staging directory in ${CERTS_DIR} is not root's own"
        return 1
    fi
}

# Runs from inside the certificates directory. $1 staging directory, $2 CA directory, $3 CN,
# $4 SAN file (absolute).
_dc_issue_pair() (
    _dc_enter_stage "$1" || return 1

    _dc_write_leaf_config leaf.cnf "$3" "$4" || return 1
    if ! (umask 077; openssl req -new -nodes -newkey rsa:2048 -sha256 \
        -keyout "${CERT_KEY_FILE}" -out dashboard.csr -config leaf.cnf >/dev/null 2>&1); then
        err "OpenSSL could not create the dashboard certificate request"
        return 1
    fi
    _dci_serial=$(openssl rand -hex 16) || return 1
    if ! openssl x509 -req -sha256 -days 3650 -set_serial "0x${_dci_serial}" \
        -in dashboard.csr -CA "$2/root-ca.pem" -CAkey "$2/root-ca.key" -passin pass: \
        -extfile leaf.cnf -extensions v3_leaf -out "${CERT_FILE}" >/dev/null 2>&1; then
        err "OpenSSL could not sign the dashboard certificate with $2/root-ca.pem"
        return 1
    fi
    _dc_validate_pair "${CERT_FILE}" "${CERT_KEY_FILE}" "$2/root-ca.pem" || return 1

    chown "${SERVICE_USER}:${SERVICE_USER}" "${CERT_FILE}" "${CERT_KEY_FILE}" || return 1
    chmod 0400 "${CERT_FILE}" "${CERT_KEY_FILE}" || return 1
    ln -T -- "${CERT_KEY_FILE}" "../${CERT_KEY_FILE}" || return 1
    ln -T -- "${CERT_FILE}" "../${CERT_FILE}" || return 1
    _wazuh_restorecon "../${CERT_KEY_FILE}" || return 1
    _wazuh_restorecon "../${CERT_FILE}" || return 1
    log "published ${CERTS_DIR}/${CERT_KEY_FILE} and ${CERT_FILE} (${SERVICE_USER}, 0400); serial ${_dci_serial}"
)

# Runs from inside the certificates directory. $1 staging directory, $2 the shared anchor.
_dc_install_anchor() (
    _dc_enter_stage "$1" || return 1
    cat -- "$2" >"${CERT_CA_FILE}" || return 1
    chown "${SERVICE_USER}:${SERVICE_USER}" "${CERT_CA_FILE}" || return 1
    chmod 0400 "${CERT_CA_FILE}" || return 1
    ln -T -- "${CERT_CA_FILE}" "../${CERT_CA_FILE}" || return 1
    _wazuh_restorecon "../${CERT_CA_FILE}"
)

# Under the shared lock, so two packages installing at once cannot both mint a CA.
_dc_ensure_locked() (
    _dce_ca_dir=$(wazuh_ca_get_dir) || return 1

    # The configuration directory is the service user's. certs/ is only ever entered through
    # _dc_enter_child, and everything after that works relative to it.
    if [ -L "${CONFIG_DIR}" ] || [ ! -d "${CONFIG_DIR}" ]; then
        err "${CONFIG_DIR} is not a directory"
        return 1
    fi
    cd -P -- "${CONFIG_DIR}" || return 1
    _dce_created=0
    if ! _dc_exists certs; then
        (umask 077; mkdir -m 0700 certs) || { err "cannot create ${CERTS_DIR}"; return 1; }
        _dce_created=1
        log "created ${CERTS_DIR}"
    fi
    _dc_enter_child certs || return 1
    if [ "${_dce_created}" -eq 1 ] && [ "$(stat -c '%u:%a' . 2>/dev/null)" != "0:700" ]; then
        err "${CERTS_DIR} changed while certificates were being issued"
        return 1
    fi

    _dce_state=absent
    if _dc_exists "${CERT_FILE}" && _dc_exists "${CERT_KEY_FILE}"; then
        _dce_state=complete
    elif _dc_exists "${CERT_FILE}" || _dc_exists "${CERT_KEY_FILE}"; then
        err "only one of ${CERT_FILE} and ${CERT_KEY_FILE} exists in ${CERTS_DIR}; refusing to complete it"
        return 1
    fi

    # Mint the CA only onto a clean slate: dashboard material without a CA was provisioned by
    # someone else, and a new anchor would not be the one it trusts.
    if ! _dc_exists "${_dce_ca_dir}/root-ca.pem" && ! _dc_exists "${_dce_ca_dir}/root-ca.key"; then
        if [ "${_dce_state}" = complete ]; then
            _dc_validate_pair "${CERT_FILE}" "${CERT_KEY_FILE}" "" || return 1
            log "${CERTS_DIR} already holds a certificate pair and ${_dce_ca_dir} has no CA; no CA is created"
            log "kept ${CERT_FILE}: $(_dc_describe_cert "${CERT_FILE}")"
            return 0
        fi
        if _dc_exists "${CERT_CA_FILE}"; then
            err "${CERTS_DIR}/${CERT_CA_FILE} exists but there is no CA in ${_dce_ca_dir}; refusing to create another CA"
            return 1
        fi
        _dce_ca_was=absent
    elif _dc_exists "${_dce_ca_dir}/root-ca.key"; then
        _dce_ca_was=complete
    else
        _dce_ca_was=anchor
    fi
    if ! _wazuh_ca_ensure_locked; then
        err "the shared root CA in ${_dce_ca_dir} could not be created or is not valid"
        return 1
    fi
    case "${_dce_ca_was}" in
        absent)
            log "created the shared root CA in ${_dce_ca_dir}: $(_dc_describe_cert "${_dce_ca_dir}/root-ca.pem")"
            ;;
        complete)
            log "reusing the shared root CA in ${_dce_ca_dir}: $(_dc_describe_cert "${_dce_ca_dir}/root-ca.pem")"
            ;;
        anchor)
            log "the shared root CA in ${_dce_ca_dir} has no private key: it is trusted but cannot issue;" \
                "$(_dc_describe_cert "${_dce_ca_dir}/root-ca.pem")"
            ;;
    esac

    _dce_stage=$(mktemp -d .stage.XXXXXX) || return 1
    trap 'rm -rf -- "${_dce_stage}"' 0
    trap 'exit 130' 1 2 3 15
    chmod 0700 "${_dce_stage}" || return 1

    if _dc_exists "${CERT_CA_FILE}"; then
        if [ "$(_dc_fingerprint "${CERT_CA_FILE}")" != "$(_dc_fingerprint "${_dce_ca_dir}/root-ca.pem")" ]; then
            log "${CERTS_DIR}/${CERT_CA_FILE} is not the CA in ${_dce_ca_dir}; it is kept as it is:" \
                "$(_dc_describe_cert "${CERT_CA_FILE}")"
        else
            log "${CERTS_DIR}/${CERT_CA_FILE} is already the shared root CA"
        fi
    else
        _dc_install_anchor "${_dce_stage}" "${_dce_ca_dir}/root-ca.pem" || return 1
        log "installed ${CERTS_DIR}/${CERT_CA_FILE} from ${_dce_ca_dir}"
    fi

    if [ "${_dce_state}" = complete ]; then
        _dc_validate_pair "${CERT_FILE}" "${CERT_KEY_FILE}" "" || return 1
        log "${CERTS_DIR} already holds a certificate pair; it is kept as it is"
        log "kept ${CERT_FILE}: $(_dc_describe_cert "${CERT_FILE}")"
        if ! openssl verify -CAfile "${_dce_ca_dir}/root-ca.pem" "${CERT_FILE}" >/dev/null 2>&1; then
            log "${CERT_FILE} does not chain to the shared root CA; it is kept as the operator's"
        fi
    else
        if ! _dc_exists "${_dce_ca_dir}/root-ca.key"; then
            err "the CA in ${_dce_ca_dir} has no private key, so no certificate can be issued from it"
            return 1
        fi
        _dce_node=$(_dc_node_name) || return 1
        # The SAN list goes into the staging directory, which only root can reach.
        _dce_sans_file="$(pwd -P)/${_dce_stage}/sans"
        _dc_sans "${_dce_node}" "${_dce_sans_file}.source" >"${_dce_sans_file}" || return 1
        [ -s "${_dce_sans_file}.source" ] && log "$(cat -- "${_dce_sans_file}.source")"
        log "issuing ${CERT_FILE} for CN ${_dce_node} from ${_dce_ca_dir}" \
            "(RSA 2048, SHA-256, 3650 days, serverAuth and clientAuth);" \
            "SANs $(tr '\n' ' ' <"${_dce_sans_file}" | sed 's/ $//')"
        _dc_issue_pair "${_dce_stage}" "${_dce_ca_dir}" "${_dce_node}" "${_dce_sans_file}" || return 1
        log "issued ${CERTS_DIR}/${CERT_FILE}: $(_dc_describe_cert "${CERT_FILE}")"
        _dce_text=$(openssl x509 -in "${CERT_FILE}" -noout -text 2>/dev/null) || _dce_text=""
        log "${CERT_FILE} SANs: $(printf '%s\n' "${_dce_text}" | sed -n '/X509v3 Subject Alternative Name:/{n;s/^ *//p;}')"
    fi

    # A directory created here gets wazuh-certs-tool's layout; an existing one is the operator's.
    # Applied to `.`, the directory we are in, never to a name the service user could swap.
    if [ "${_dce_created}" -eq 1 ]; then
        rm -rf -- "${_dce_stage}"
        chown "${SERVICE_USER}:${SERVICE_USER}" . || return 1
        chmod 0500 . || return 1
        _wazuh_restorecon "${CERTS_DIR}" || return 1
        log "set ${CERTS_DIR} to ${SERVICE_USER}:${SERVICE_USER} 0500"
    fi
    log "the TLS certificates in ${CERTS_DIR} are in place"
)

resolve_certificates() {
    if [ "$(id -u)" != 0 ]; then
        log "not running as root; certificates are not issued"
        return 0
    fi
    _dc_require || return 1
    _rcs_ca=$(wazuh_ca_get_dir 2>/dev/null) || _rcs_ca="(unresolved)"
    log "resolving the TLS certificates in ${CERTS_DIR} (shared CA directory: ${_rcs_ca})"
    _wazuh_with_lock _dc_ensure_locked
}

# The --clear half: the dashboard's three files, and the CA only when it has a private key -- one
# minted on this host, and so baked into the image. An anchor-only CA was handed to the host and
# stays. Runs under the shared lock like every other write to the CA directory.
_dc_clear_locked() (
    for _dcc_file in "${CERT_FILE}" "${CERT_KEY_FILE}" "${CERT_CA_FILE}"; do
        if _dc_exists "${CERTS_DIR}/${_dcc_file}"; then
            rm -f -- "${CERTS_DIR}/${_dcc_file}" || return 1
            log "removed ${CERTS_DIR}/${_dcc_file}"
        fi
    done
    _dcc_ca=$(wazuh_ca_get_dir 2>/dev/null) || _dcc_ca=""
    if [ -n "${_dcc_ca}" ] && _dc_exists "${_dcc_ca}/root-ca.key"; then
        rm -f -- "${_dcc_ca}/root-ca.key" "${_dcc_ca}/root-ca.pem" "${_dcc_ca}/root-ca.srl" || return 1
        log "removed the CA in ${_dcc_ca}"
    elif [ -n "${_dcc_ca}" ] && _dc_exists "${_dcc_ca}/root-ca.pem"; then
        log "kept the CA in ${_dcc_ca}: it has no private key, so it was not created on this host"
    fi
)

clear_certificates() {
    [ "$(id -u)" = 0 ] || return 0
    command -v _wazuh_with_lock >/dev/null 2>&1 || return 1
    _wazuh_with_lock _dc_clear_locked
}

# -----------------------------------------------------------------------------------------
# --clear
#
# The one destructive path in a tool whose every other rule is "never overwrite, never repair,
# leave what is already there alone". It exists for exactly one situation: an image built by
# installing the package, which ran the resolver in its postinst and therefore baked this host's
# credentials into a layer that every container will share.
#
# It removes the AI assistant key as well: an image that baked one would hand every container the
# same key. Provider API keys already encrypted with it can no longer be decrypted, which is
# nothing on an image that was never used, and exactly why this is not something a running host
# should ever do.
#
# What it deliberately does NOT remove: anything in the credentials file. The dashboard owns no
# key there; every one belongs to a sibling, and removing it is the sibling's --clear.
# -----------------------------------------------------------------------------------------

dashboard_is_running() {
    if command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet wazuh-dashboard.service 2>/dev/null; then
        return 0
    fi
    [ -f "${PID_FILE}" ] || return 1
    _dir_pid=$(cat "${PID_FILE}" 2>/dev/null)
    [ -n "${_dir_pid}" ] || return 1
    # A stale pidfile from an unclean stop is not a running dashboard.
    kill -0 "${_dir_pid}" 2>/dev/null
}

clear_credentials() {
    if dashboard_is_running; then
        err "refusing to clear credentials while the dashboard is running"
        err "        stop it first: systemctl stop wazuh-dashboard"
        return 1
    fi

    if ! clear_certificates; then
        err "could not remove the dashboard certificates or the CA"
        return 1
    fi

    if [ ! -f "${KEYSTORE_FILE}" ]; then
        log "there is no keystore in ${KEYSTORE_FILE}; nothing to clear"
        return 0
    fi
    if [ ! -x "${KEYSTORE_BIN}" ]; then
        err "cannot clear the keystore: ${KEYSTORE_BIN} is missing"
        return 1
    fi

    keystore_load
    for _cc_entry in ${LADDER_ENTRIES} ${OWNED_ENTRIES}; do
        keystore_has "${_cc_entry}" || continue
        keystore remove "${_cc_entry}" </dev/null >/dev/null 2>&1
    done

    # Never claim it. This path exists so that nothing of this host's credentials reaches an image,
    # and a cleared-but-not-cleared keystore is the failure it is meant to stop -- so the result is
    # read back rather than inferred from exit codes.
    keystore_load
    _cc_left=""
    for _cc_entry in ${LADDER_ENTRIES} ${OWNED_ENTRIES}; do
        keystore_has "${_cc_entry}" && _cc_left="${_cc_left} ${_cc_entry}"
    done
    if [ -n "${_cc_left}" ]; then
        err "could not remove from the keystore:${_cc_left}"
        return 1
    fi

    log "removed ${LADDER_ENTRIES} ${OWNED_ENTRIES} from the keystore"
    log "cleared; the next start resolves from nothing"
    return 0
}

# -----------------------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------------------

if [ "${MODE}" = "clear" ]; then
    clear_credentials
    exit $?
fi

if [ "${MODE}" = "install" ] || [ "${MODE}" = "upgrade" ]; then
    credentials_file_ensure || true
fi

if keystore_ensure; then
    KEYSTORE_READY=1
else
    mark_unresolved "keystore"
fi

if ! config_resolves_kibanaserver; then
    # A username set in the yml is the operator's: never write kibanaserver over it.
    if config_has opensearch.username; then
        resolve_consumed WAZUH_INDEXER_KIBANASERVER_PASSWORD INDEXER_PASSWORD \
            opensearch.password
    else
        resolve_consumed WAZUH_INDEXER_KIBANASERVER_PASSWORD INDEXER_PASSWORD \
            opensearch.password opensearch.username kibanaserver
    fi
fi
if ! config_resolves_wui; then
    resolve_consumed WAZUH_MANAGER_WUI_PASSWORD API_PASSWORD \
        wazuh_core.hosts.default.password
fi

# Owned, and only at install and start -- an upgrade adds no secret. Its result never counts
# towards the verdict: the AI assistant is optional.
if [ "${MODE}" = "install" ] || [ "${MODE}" = "prestart" ]; then
    resolve_encryption_key || true
fi

# Certificates are issued once, on a fresh install -- see their section. Their result never counts
# towards the verdict, so this is the one moment a failure can be reported, and it is said plainly
# rather than left for the operator to meet as a missing file when the dashboard starts.
if [ "${MODE}" = "install" ]; then
    if ! resolve_certificates; then
        err "the dashboard has no TLS certificates and this install could not issue them"
        err "        provision ${CERT_FILE}, ${CERT_KEY_FILE} and ${CERT_CA_FILE} into ${CERTS_DIR}"
        err "        (e.g. with wazuh-certs-tool); the dashboard will not start without them"
    fi
else
    log "TLS certificates are only issued on a fresh install; ${CERTS_DIR} is left as it is"
fi

# The installer has no opinion about whether the component can run: no warning, no failure, no
# special state. Nothing checks credentials until something needs them.
if [ "${MODE}" = "install" ] || [ "${MODE}" = "upgrade" ]; then
    exit 0
fi

if [ -z "${UNRESOLVED}" ] && [ -z "${INVALID}" ]; then
    exit 0
fi

CREDENTIALS_FILE=$(wazuh_env_get_file 2>/dev/null) || CREDENTIALS_FILE="/etc/wazuh/credentials.env"

# The message goes to the journal, which is where someone looks when a service will not start.
# It names every missing key and where to set it, and never prints a value.
for _key in ${INVALID}; do
    err "INVALID ${_key}: the supplied value does not meet the password policy"
    err "        (12-64 characters from A-Z a-z 0-9 . , _ + : @ % ^ = ~ -, with at least one letter and one digit)"
    err "        correct it in ${CREDENTIALS_FILE} and start the service again"
done

# A key that went missing because the keystore itself is unusable is reported once, as that.
case " ${UNRESOLVED} " in
    *" keystore "*)
        err "MISSING keystore: ${KEYSTORE_FILE} could not be created or read"
        exit 1
        ;;
esac

if [ "${CREDENTIALS_FILE_REFUSED}" -eq 1 ]; then
    err "REFUSED ${CREDENTIALS_FILE}: it, or a directory above it, fails the ownership, mode or format rules"
    err "        the reason is logged above by wazuh-credentials; it is never repaired automatically"
fi

for _key in ${UNRESOLVED}; do
    case "${_key}" in
        WAZUH_INDEXER_KIBANASERVER_PASSWORD)
            err "MISSING WAZUH_INDEXER_KIBANASERVER_PASSWORD (the indexer's kibanaserver account)"
            err "        set it in ${CREDENTIALS_FILE}, or install wazuh-indexer on this host first"
            ;;
        WAZUH_MANAGER_WUI_PASSWORD)
            err "MISSING WAZUH_MANAGER_WUI_PASSWORD (the manager's wazuh-wui account)"
            err "        set it in ${CREDENTIALS_FILE}, or install wazuh-manager on this host first"
            ;;
        *)
            err "MISSING ${_key}"
            err "        set it in ${CREDENTIALS_FILE}"
            ;;
    esac
done

exit 1
