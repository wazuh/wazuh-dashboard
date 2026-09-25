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
# This file adds only what is specific to the dashboard, and that is little: the dashboard OWNS
# NOTHING and CONSUMES TWO PASSWORDS, both into its keystore.
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
# The same script runs at three moments, and the difference between them is the whole design:
#
#   --install    From a FRESH postinst / %post -- never from an upgrade. Stores what it can, and has
#                no opinion about whether the dashboard can run. Never fails: a maintainer script
#                that aborts leaves the package half-configured, breaks `apt install -f` and fails
#                image builds. Exits 0 whatever it could not resolve, and says nothing about it.
#
#   --upgrade    From postinst / %post when a previous version was already installed. Identical to
#                --install: once both keystore entries exist step 0 is true for both, so the only
#                values it can fill in are the ones this host never had, and nothing that is
#                already configured changes.
#
#   --prestart   From the unit's ExecStartPre=+ and from the SysV init script's start. Runs the same
#                ladder again, not merely a check, so a dashboard installed before the indexer or
#                the manager picks up what became available since and configures itself. Exits
#                non-zero naming every key it could not resolve.
#
#   --clear      Removes every credential this dashboard stores, so the next --install or
#                --prestart resolves from nothing. Nothing in the product calls it: it exists for
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

# Every keystore entry this script may write, and so every one --clear removes.
LADDER_ENTRIES="opensearch.username opensearch.password wazuh_core.hosts.default.password"

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
# --clear
#
# The one destructive path in a tool whose every other rule is "never overwrite, never repair,
# leave what is already there alone". It exists for exactly one situation: an image built by
# installing the package, which ran the resolver in its postinst and therefore baked this host's
# credentials into a layer that every container will share.
#
# What it deliberately does NOT remove:
#
#   * Anything in the credentials file. The dashboard owns no key there; every one belongs to a
#     sibling, and removing it is the sibling's --clear.
#   * wazuh_ai_assistant.encryptionKey. It is a secret the dashboard owns, generated by the
#     maintainer scripts, not a credential this ladder resolves.
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

    if [ ! -f "${KEYSTORE_FILE}" ]; then
        log "there is no keystore in ${KEYSTORE_FILE}; nothing to clear"
        return 0
    fi
    if [ ! -x "${KEYSTORE_BIN}" ]; then
        err "cannot clear the keystore: ${KEYSTORE_BIN} is missing"
        return 1
    fi

    keystore_load
    for _cc_entry in ${LADDER_ENTRIES}; do
        keystore_has "${_cc_entry}" || continue
        keystore remove "${_cc_entry}" </dev/null >/dev/null 2>&1
    done

    # Never claim it. This path exists so that nothing of this host's credentials reaches an image,
    # and a cleared-but-not-cleared keystore is the failure it is meant to stop -- so the result is
    # read back rather than inferred from exit codes.
    keystore_load
    _cc_left=""
    for _cc_entry in ${LADDER_ENTRIES}; do
        keystore_has "${_cc_entry}" && _cc_left="${_cc_left} ${_cc_entry}"
    done
    if [ -n "${_cc_left}" ]; then
        err "could not remove from the keystore:${_cc_left}"
        return 1
    fi

    log "removed ${LADDER_ENTRIES} from the keystore"
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
