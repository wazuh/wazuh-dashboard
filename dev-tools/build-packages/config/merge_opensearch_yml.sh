#!/bin/sh
# Purpose: Merge new default settings from a packaged opensearch_dashboards.yml
# into the active /etc/wazuh-dashboard/opensearch_dashboards.yml, only adding
# keys that do not already exist. Prefers deep additive merge with Mike Farah
# yq v4+; otherwise falls back to conservative strategies without overwriting
# user-defined values.
#
# Design notes (clean code / maintainability):
# - Single-responsibility functions for argument parsing, capability detection,
#   merge strategies, permission handling, and logging.
# - All hardcoded values consolidated as constants below for easy change.
# - POSIX sh compatible (no bashisms) to maximize portability.
# - Explicit and defensive checks; exits cleanly if nothing to do.

set -eu

# ----------------------------- Constants ------------------------------------
DEFAULT_CONFIG_DIR="/etc/wazuh-dashboard"
DEFAULT_TARGET_FILE="opensearch_dashboards.yml"
# Candidate suffixes produced by package managers: rpm, dpkg, ucf
PACKAGE_SUFFIXES="rpmnew dpkg-dist dpkg-new ucf-dist"
DEFAULT_OWNER_USER="wazuh-dashboard"
DEFAULT_FILE_MODE="0640"

# ---------------------------- Logging utils ---------------------------------
log_info()  { echo "[INFO]  $*" 1>&2; }
log_warn()  { echo "[WARN]  $*" 1>&2; }
log_error() { echo "[ERROR] $*" 1>&2; }

usage() {
  cat 1>&2 <<USAGE
Usage: $0 [--config-dir DIR] [--help]

Merges defaults from a packaged ${DEFAULT_TARGET_FILE} into the active file,
adding only missing keys. Deep additive merge is used when Mike Farah yq v4+
is available; otherwise a conservative append of missing top-level blocks is
performed.
USAGE
}

# --------------------------- Helper functions -------------------------------
ensure_permissions() {
  # Ensure ownership (if user exists) and mode, but never fail the merge.
  if command -v id >/dev/null 2>&1 && id "$DEFAULT_OWNER_USER" >/dev/null 2>&1; then
    chown "$DEFAULT_OWNER_USER":"$DEFAULT_OWNER_USER" "$1" || true
  fi
  chmod "$DEFAULT_FILE_MODE" "$1" || true
}

detect_new_config_path() {
  # Args: $1 = target path without suffix
  # Echoes path to the packaged new config if found, else empty
  base="$1"
  for s in $PACKAGE_SUFFIXES; do
    cand="${base}.$s"
    if [ -f "$cand" ]; then
      echo "$cand"
      return 0
    fi
  done
  echo ""
}

detect_yq_variant() {
  # Echoes one of: farah | legacy | none
  if command -v yq >/dev/null 2>&1; then
    if yq --version 2>&1 | grep -Ei 'mikefarah|https://github.com/mikefarah/yq' >/dev/null 2>&1; then
      echo "farah"
      return 0
    fi
    echo "legacy"
    return 0
  fi
  echo "none"
}

create_tmp_workspace() {
  TMP_DIR=$(mktemp -d)
  APPEND_FILE="$TMP_DIR/append.yml"
  PATCH_FILE="$TMP_DIR/patch.yml"
  MERGED_FILE="$TMP_DIR/merged.yml"
  ADDED_KEYS_FILE="$TMP_DIR/added_keys.txt"
  OLD_JSON="$TMP_DIR/old.json"
  NEW_JSON="$TMP_DIR/new.json"
  export TMP_DIR APPEND_FILE PATCH_FILE MERGED_FILE ADDED_KEYS_FILE OLD_JSON NEW_JSON
}

cleanup() {
  if [ "${TMP_DIR:-}" != "" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR" || true
  fi
}

collect_existing_top_keys() {
  # Args: $1 = yaml file, $2 = output file with keys (one per line)
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      if (match($0, /^[[:space:]]*([^:#]+)[[:space:]]*:/, m)) {
        key=m[1]; gsub(/[[:space:]]+$/, "", key); print key
      }
    }
  ' "$1" | sed 's/[[:space:]]*$//' | sort -u > "$2"
}

append_missing_top_level_blocks() {
  # Args: $1 = target file, $2 = new file
  # Modifies: APPEND_FILE, ADDED_KEYS_FILE
  collect_existing_top_keys "$1" "$TMP_DIR/existing_keys.txt"
  : > "$APPEND_FILE"; : > "$ADDED_KEYS_FILE"
  awk -v existing="$TMP_DIR/existing_keys.txt" -v added="$ADDED_KEYS_FILE" -v out="$APPEND_FILE" '
    BEGIN { while ((getline k < existing) > 0) { have[k]=1 } close(existing) }
    { lines[NR]=$0 }
    END {
      n=NR
      for (i=1; i<=n; i++) {
        line=lines[i]
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
        if (line ~ /^[^[:space:]#][^:]*:[[:space:]]*/) {
          key=line; sub(/:.*/, "", key); gsub(/[[:space:]]+$/, "", key)
          if (!(key in start)) { order[++orderN]=key; start[key]=i }
        }
      }
      for (idx=1; idx<=orderN; idx++) {
        k=order[idx]; s=start[k]; e=n; if (idx<orderN) { nk=order[idx+1]; e=start[nk]-1 }
        if (!(k in have) && !(k in printed)) {
          for (j=s; j<=e; j++) print lines[j] >> out
          print k >> added
          printed[k]=1
        }
      }
    }
  ' "$2"

  if [ -s "$APPEND_FILE" ]; then
    echo "# --- Added new default settings on $(date -u +"%Y-%m-%dT%H:%M:%SZ") ---" >> "$1"
    cat "$APPEND_FILE" >> "$1"
    ensure_permissions "$1"
  fi
}

merge_with_yq_v4() {
  # Args: $1 target, $2 new
  # Build a patch containing only missing scalar leaves and deep-merge without overwrite
  yq ea -n '
    (select(fileIndex==0)) as $old |
    (select(fileIndex==1)) as $new |
    reduce ($new | paths(scalars)) as $p ({};
      (try ($old | getpath($p)) catch null) as $ov |
      if $ov == null then setpath($p; $new | getpath($p)) else . end
    )
  ' "$1" "$2" > "$PATCH_FILE" || true

  if [ -s "$PATCH_FILE" ] && [ "$(yq e 'length == 0' "$PATCH_FILE" 2>/dev/null || echo false)" != "true" ]; then
    yq ea -n '
      (select(fileIndex==0)) as $old |
      (select(fileIndex==1)) as $patch |
      $old *d $patch
    ' "$1" "$PATCH_FILE" > "$MERGED_FILE" && mv "$MERGED_FILE" "$1"
    ensure_permissions "$1"

    # Best-effort log of added top-level keys
    yq e 'keys | .[]' "$PATCH_FILE" 2>/dev/null | sed 's/^/  - /' > "$ADDED_KEYS_FILE" || true
    if [ -s "$ADDED_KEYS_FILE" ]; then
      log_info "Merged new default keys into $1:" ; cat "$ADDED_KEYS_FILE" 1>&2 || true
    fi
  else
    log_info "No missing keys to merge (yq v4)."
  fi
}

merge_with_yq_legacy() {
  # Args: $1 target, $2 new
  # Strategy: append missing top-level blocks; then best-effort nested additions for common blocks.
  append_missing_top_level_blocks "$1" "$2"

  # Only attempt nested patching if nothing was appended (i.e., keys exist already)
  if [ ! -s "$APPEND_FILE" ] && command -v jq >/dev/null 2>&1; then
    yq '.' "$1" > "$OLD_JSON" 2>/dev/null || true
    yq '.' "$2" > "$NEW_JSON" 2>/dev/null || true
    if [ -s "$OLD_JSON" ] && [ -s "$NEW_JSON" ]; then
      MISSING_NESTED=$(jq -s '[ (.[1]|paths(scalars)) as $p | select(((.[0]|keys)|index($p[0])) and ((.[0]|getpath($p)? // null) == null)) ] | length' "$OLD_JSON" "$NEW_JSON" 2>/dev/null || echo 0)
      if [ "${MISSING_NESTED:-0}" -gt 0 ] 2>/dev/null; then
        # Special-case merge for uiSettings only (textual, additive, non-overwrite)
        if grep -q '^uiSettings:' "$1" && grep -q '^uiSettings:' "$2"; then
          awk '/^uiSettings:[[:space:]]*$/{flag=1; next} /^[^[:space:]#][^:]*:[[:space:]]*/{if(flag){exit}} flag{print}' "$2" > "$TMP_DIR/ui_block.new"
          if [ -s "$TMP_DIR/ui_block.new" ]; then
            awk -v tmpfile="$TMP_DIR/ui_block.new" '
              BEGIN{printed=0}
              /^uiSettings:[[:space:]]*$/ {print; ui=1; next}
              /^[^[:space:]#][^:]*:[[:space:]]*/ { if (ui && !printed) { while ((getline line < tmpfile) > 0) { if (line != "" && system("grep -Fqx \"" line "\" \"" FILENAME "\"") != 0) print line } close(tmpfile); printed=1; ui=0 } }
              {print}
              END{ if (ui && !printed) { while ((getline line < tmpfile) > 0) { if (line != "" && system("grep -Fqx \"" line "\" \"" FILENAME "\"") != 0) print line } close(tmpfile) } }
            ' "$1" > "$TMP_DIR/target.with.ui.yml" 2>/dev/null || true
            if [ -s "$TMP_DIR/target.with.ui.yml" ]; then
              mv "$TMP_DIR/target.with.ui.yml" "$1"
              ensure_permissions "$1"
            fi
          fi
        fi
      fi
    fi
  fi
}

fallback_append_only() {
  # Args: $1 target, $2 new
  append_missing_top_level_blocks "$1" "$2"
  if [ -s "$ADDED_KEYS_FILE" ]; then
    log_info "Merged new default keys into $1:" ; sed 's/^/  - /' "$ADDED_KEYS_FILE" 1>&2 || true
  else
    log_info "No missing top-level blocks to append."
  fi
}

# ------------------------------ Main ----------------------------------------
CONFIG_DIR="$DEFAULT_CONFIG_DIR"
TARGET_FILE="$DEFAULT_TARGET_FILE"

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir)
      CONFIG_DIR="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      log_warn "Ignoring unknown argument: $1"; shift ;;
  esac
done

TARGET_PATH="${CONFIG_DIR}/${TARGET_FILE}"

NEW_PATH=$(detect_new_config_path "$TARGET_PATH")

# Nothing to do if there is no pending new config file or target is missing
if [ -z "$NEW_PATH" ] || [ ! -f "$TARGET_PATH" ]; then
  exit 0
fi

create_tmp_workspace
trap cleanup EXIT INT TERM HUP

YQ_VARIANT=$(detect_yq_variant)

case "$YQ_VARIANT" in
  farah)
    merge_with_yq_v4 "$TARGET_PATH" "$NEW_PATH" ;;
  legacy)
    merge_with_yq_legacy "$TARGET_PATH" "$NEW_PATH" ;;
  none)
    fallback_append_only "$TARGET_PATH" "$NEW_PATH" ;;
esac

# Always remove the packaged new config file once handled (idempotent)
if [ -f "$NEW_PATH" ]; then
  rm -f "$NEW_PATH" || true
fi

exit 0

# Remove the pending new config file to avoid future prompts
rm -f "$NEW_PATH"
rm -rf "$TMP_DIR"
exit 0
