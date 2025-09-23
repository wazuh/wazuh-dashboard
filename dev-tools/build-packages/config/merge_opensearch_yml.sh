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
# log_info
#   Emit an informational message to stderr. Useful for non‑critical traces.
#   Example:
#     log_info "Merged defaults into /etc/wazuh-dashboard/opensearch_dashboards.yml"
log_info()  { echo "[INFO]  $*" 1>&2; }

# log_warn
#   Emit a warning to stderr. Useful for unknown arguments or operations that
#   continue with default behavior.
#   Example:
#     log_warn "Ignoring unknown argument: --foo"
log_warn()  { echo "[WARN]  $*" 1>&2; }

# log_error
#   Emit an error to stderr. Does NOT terminate the script; intended to record
#   non‑critical failures that should not abort the merge.
#   Example:
#     log_error "Could not set ownership; continuing"
log_error() { echo "[ERROR] $*" 1>&2; }

# usage
#   Show script usage help.
#   Example:
#     ./merge_opensearch_yml.sh --help
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
# ensure_permissions
#   Ensure destination file ownership/group and permissions. If the service
#   user does not exist, do not fail.
#
#   Args:
#     $1: path to file whose ownership/permissions will be adjusted.
#
#   Examples:
#     ensure_permissions "/etc/wazuh-dashboard/opensearch_dashboards.yml"
#
#   Notes:
#   - Does not abort if `chown`/`chmod` fail; the merge is already done and we
#     do not want to lose the work.
ensure_permissions() {
  # Ensure ownership (if user exists) and mode, but never fail the merge.
  if command -v id >/dev/null 2>&1 && id "$DEFAULT_OWNER_USER" >/dev/null 2>&1; then
    chown "$DEFAULT_OWNER_USER":"$DEFAULT_OWNER_USER" "$1" || true
  fi
  chmod "$DEFAULT_FILE_MODE" "$1" || true
}

# detect_new_config_path
#   Look for new configuration artifacts produced by the package manager
#   (e.g., `.rpmnew`, `.dpkg-dist`, `.dpkg-new`, `.ucf-dist`) for the target
#   file. Prints the first match to stdout or empty if none found.
#
#   Args:
#     $1: base path of the target file without suffix (e.g., /etc/.../file.yml)
#
#   Example:
#     detect_new_config_path "/etc/wazuh-dashboard/opensearch_dashboards.yml"
#     # => /etc/wazuh-dashboard/opensearch_dashboards.yml.rpmnew | ""
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
  # Determine which yq variant is available for choosing the merge strategy.
  # Echo to stdout one of: farah | legacy | none
  # - farah: Mike Farah yq v4+, supports powerful YAML expressions and *d merge.
  # - legacy: another yq (or wrapper) present, no compatibility guarantees.
  # - none: no yq available; use conservative fallback.
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

# create_tmp_workspace
#   Create a temporary directory for intermediate files (patch, append, json,
#   etc.) and export paths as global variables. Removed in `cleanup` via trap.
#
#   Example:
#     create_tmp_workspace
#     # Global variables become available: $TMP_DIR, $PATCH_FILE, ...
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
  # Remove temporary workspace if it exists. Invoked automatically on
  # EXIT/INT/TERM/HUP via the trap; reentrant-safe.
  if [ "${TMP_DIR:-}" != "" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR" || true
  fi
}

collect_existing_top_keys() {
  # Extract top‑level keys from YAML ignoring blank lines and comments, write
  # them sorted and unique to the output file.
  #
  # Args:
  #   $1: input YAML file
  #   $2: output file with one key per line
  #
  # Example:
  #   collect_existing_top_keys target.yml out.txt
  #   # out.txt ->
  #   # server
  #   # logging
  #   # uiSettings
  awk '
    # Ignore top-level comments and blank lines
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }

    # If the line matches "key:" (ignoring values/comments), extract it.
    # Only first-level (non-indented) keys are considered.
    {
      if (match($0, /^[[:space:]]*([^:#]+)[[:space:]]*:/, m)) {
        key = m[1]
        gsub(/[[:space:]]+$/, "", key)  # Trim trailing whitespace
        print key
      }
    }
  ' "$1" \
  | sed 's/[[:space:]]*$//' \
  | sort -u > "$2"
}

append_missing_top_level_blocks() {
  # Append to the destination file any top‑level blocks present in the "new"
  # file but absent in the target. Does not overwrite existing keys nor modify
  # already present blocks; only copies whole missing blocks.
  #
  # Args:
  #   $1: destination file (e.g., /etc/wazuh-dashboard/opensearch_dashboards.yml)
  #   $2: new file (e.g., opensearch_dashboards.yml.rpmnew)
  # Side effects:
  #   Writes APPEND_FILE with content to append and ADDED_KEYS_FILE with the
  #   list of added top‑level keys.
  #
  # Example:
  #   target.yml: has "server:" and "logging:"
  #   new.yml:    has "server:", "logging:", "uiSettings:"
  #   => The full "uiSettings:" block is appended to target.yml; existing
  #      blocks remain intact.
  collect_existing_top_keys "$1" "$TMP_DIR/existing_keys.txt"
  : > "$APPEND_FILE"; : > "$ADDED_KEYS_FILE"
  awk \
    -v existing="$TMP_DIR/existing_keys.txt" \
    -v added="$ADDED_KEYS_FILE" \
    -v out="$APPEND_FILE" \
    '
    # Load current destination keys into have[]
    BEGIN {
      while ((getline k < existing) > 0) {
        have[k] = 1
      }
      close(existing)
    }

    # Buffer all lines from the new file for second pass
    {
      lines[NR] = $0
    }

    END {
      n = NR

      # Detect top-level block starts and record their order
      for (i = 1; i <= n; i++) {
        line = lines[i]
        # Skip comments and blank lines
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) {
          continue
        }
        # A top-level block starts at column 0 (non-space, non-#) and has ':'
        if (line ~ /^[^[:space:]#][^:]*:[[:space:]]*/) {
          key = line
          sub(/:.*/, "", key)            # Strip text after ':'
          gsub(/[[:space:]]+$/, "", key)  # Trim trailing spaces
          if (!(key in start)) {
            order[++orderN] = key   # Preserve appearance order
            start[key] = i          # Record starting index
          }
        }
      }

      # Copy complete missing blocks (from start to next top-level or EOF)
      for (idx = 1; idx <= orderN; idx++) {
        k = order[idx]
        s = start[k]
        e = n
        if (idx < orderN) {
          nk = order[idx + 1]
          e = start[nk] - 1
        }
        if (!(k in have) && !(k in printed)) {
          for (j = s; j <= e; j++) {
            print lines[j] >> out   # Append block content
          }
          print k >> added          # Record added key
          printed[k] = 1
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
  # Perform a deep additive merge with yq v4 (Mike Farah) without overwriting
  # existing values. First build a "patch" containing only missing scalar leaf
  # nodes from the target, then apply `$old *d $patch`.
  #
  # Args:
  #   $1: destination file
  #   $2: new (packaged) file
  #
  # Conceptual example:
  #   old:
  #     server:
  #       port: 5601
  #   new:
  #     server:
  #       host: 0.0.0.0
  #   patch => { server: { host: 0.0.0.0 } }
  #   merge => inserts host, keeps port.
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
  # Strategy for environments with non‑Mike-Farah yq (or wrappers):
  # 1) Append missing top-level blocks (safe, non-destructive).
  # 2) If nothing appended, attempt an optional improvement: detect missing
  #    nested scalars via jq and apply a textual patch for the known `uiSettings`
  #    block (without overwriting existing lines).
  #
  # Args:
  #   $1: destination file
  #   $2: new file
  append_missing_top_level_blocks "$1" "$2"

  # Only attempt additive textual merge if nothing was appended yet (i.e.,
  # the top-level keys already exist). This step is generic for any
  # top-level block and does not depend on specific names.
  if [ ! -s "$APPEND_FILE" ]; then
        # Generic additive textual merge for all top-level blocks
        collect_existing_top_keys "$2" "$TMP_DIR/new_top_keys.txt"
        while IFS= read -r key; do
          # Only process keys that exist in destination as well
          if grep -q "^${key}:[[:space:]]*" "$1"; then
            key_re=$(printf '%s' "$key" | sed -E 's/([][(){}.^$|*+?\\])/\\\\\1/g')

            # Extract the block from the new file (without the "key:" header)
            awk \
              -v key="$key_re" \
              '
              # When the exact block header is found, begin capture
              $0 ~ "^" key ":[[:space:]]*$" { flag = 1; next }
              # On the next top-level key, end capture
              /^[^[:space:]#][^:]*:[[:space:]]*/ { if (flag) { exit } }
              # While flag is active, print lines of the block
              flag { print }
              ' "$2" > "$TMP_DIR/block.new"

            if [ -s "$TMP_DIR/block.new" ]; then
              # Insert missing lines from the new block just after the header in
              # the destination, avoiding duplicates and preserving order
          awk \
            -v key="$key_re" \
            -v tmpfile="$TMP_DIR/block.new" \
            -v dest="$1" \
            '
            # Build a set of all lines present in destination to avoid duplicates
            BEGIN {
              injected = 0
              while ((getline l < dest) > 0) {
                file_has[l] = 1
              }
              close(dest)
            }

            # When hitting the target block header, mark that we are inside it
            $0 ~ "^" key ":[[:space:]]*$" {
              print
              intarget = 1
              next
            }

            # At the next top-level key, if still in block and not injected yet,
            # add only lines that are not already present
            /^[^[:space:]#][^:]*:[[:space:]]*/ {
              if (intarget && !injected) {
                while ((getline line < tmpfile) > 0) {
                  if (line != "" && !(line in file_has)) {
                    print line
                  }
                }
                close(tmpfile)
                injected = 1
                intarget = 0
              }
            }

            # Default: print the current line unchanged
            { print }

            # If file ends while still inside block and not injected, insert pending lines
            END {
              if (intarget && !injected) {
                while ((getline line < tmpfile) > 0) {
                  if (line != "" && !(line in file_has)) {
                    print line
                  }
                }
                close(tmpfile)
              }
            }
          ' "$1" > "$TMP_DIR/target.tmp" 2>/dev/null || true

              if [ -s "$TMP_DIR/target.tmp" ]; then
                mv "$TMP_DIR/target.tmp" "$1"
                ensure_permissions "$1"
              fi
            fi
          fi
        done < "$TMP_DIR/new_top_keys.txt"
  fi
}

fallback_append_only() {
  # Fallback without yq: append only missing top-level blocks.
  # No deep merges; deliberately conservative to avoid touching user values.
  #
  # Args:
  #   $1: destination file
  #   $2: new file
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
