#!/bin/sh
# Purpose: Merge new default settings from a packaged opensearch_dashboards.yml
# into the active /etc/wazuh-dashboard/opensearch_dashboards.yml, only adding
# keys that do not already exist. Performs a conservative, non-destructive
# merge: appends whole missing top-level blocks and injects only missing
# nested lines under existing blocks; never overwrites user-defined values.
#
# Special case: for top-level keys whose values are YAML flow-style arrays
# (e.g., `key: [a, b]`) that already exist in the destination, the script
# appends only the elements that are present in the new defaults but absent in
# the destination, preserving the existing order. This enables cases like
# `plugins.security.system_indices.indices` where new indices must be added
# without reordering or duplicating user-defined values.
#
# Design notes (clean code / maintainability):
# - Single-responsibility functions for argument parsing, capability detection,
#   merge strategies, permission handling, and logging.
# - All hardcoded values consolidated as constants below for easy change.
# - POSIX sh compatible (no bashisms) to maximize portability.
# - Explicit and defensive checks; exits cleanly if nothing to do.

# Be conservative about aborting: avoid exiting on non-zero intermediate commands.
# We keep undefined-variable checks but do not use `-e` to prevent partial merges.
set -u

# ----------------------------- Constants ------------------------------------
DEFAULT_CONFIG_DIR="/etc/wazuh-dashboard"
DEFAULT_TARGET_FILE="opensearch_dashboards.yml"
# Candidate suffixes produced by package managers: rpm, dpkg, ucf
PACKAGE_SUFFIXES="rpmnew dpkg-dist dpkg-new ucf-dist"
DEFAULT_OWNER_USER="wazuh-dashboard"
DEFAULT_FILE_MODE="0640"
BACKUP_TIMESTAMP_FORMAT="%Y%m%dT%H%M%SZ"

# ---------------------------- Logging utils ---------------------------------
# log_info
#   Emit an informational message to stderr. Useful for non-critical traces.
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
#   non-critical failures that should not abort the merge.
#   Example:
#     log_error "Could not set ownership; continuing"
log_error() { echo "[ERROR] $*" 1>&2; }

# usage
#   Show script usage help.
#   Example:
#     ./merge_opensearch_yml.sh --help
usage() {
  cat 1>&2 <<'USAGE'
Usage: $0 [--config-dir DIR] [--help]

Merges defaults from a packaged ${DEFAULT_TARGET_FILE} into the active file,
adding only missing keys using a conservative strategy: append whole missing
top-level blocks and inject only missing nested lines under existing blocks.

Before merging, a timestamped backup of the destination YAML is created
alongside the file with suffix `.bak.<UTC-TS>`.
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

# backup_config_file
#   Create a timestamped backup of the destination YAML before any merge.
#   The backup is placed alongside the original with suffix `.bak.<UTC-TS>`.
#
#   Args:
#     $1: path to the destination file to back up
#
#   Notes:
#   - Does not abort on failure; logs an error and continues to be resilient
#     in packaging/upgrade flows.
backup_config_file() {
  src="$1"
  if [ ! -f "$src" ]; then
    return 0
  fi
  ts=$(date -u +"$BACKUP_TIMESTAMP_FORMAT")
  dest="${src}.bak.${ts}"
  if cp -p "$src" "$dest" 2>/dev/null; then
    log_info "Created backup: $dest"
  else
    # Try without -p as a fallback (busybox/limited cp implementations)
    if cp "$src" "$dest" 2>/dev/null; then
      log_info "Created backup: $dest"
    else
      log_error "Failed to create backup at $dest"
    fi
  fi
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
  # Extract top-level keys from YAML ignoring blank lines and comments, write
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
  # Append to the destination file any top-level blocks present in the "new"
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

textual_additive_merge() {
  # Args: $1 dest, $2 new
  append_missing_top_level_blocks "$1" "$2"

  # Only attempt additive textual merge if nothing was appended yet (i.e.,
  # the top-level keys already exist). This step is generic for any
  # top-level block and does not depend on specific names.
  if [ ! -s "$APPEND_FILE" ]; then
    set +e
    # Generic additive textual merge for all top-level blocks
    collect_existing_top_keys "$2" "$TMP_DIR/new_top_keys.txt"
    while IFS= read -r key; do
      # Only process keys that exist in destination as well
      if grep -q "^${key}:[[:space:]]*" "$1"; then
        log_info "[textual-merge] Processing existing top-level key: $key"
        key_re=$(printf '%s' "$key" | sed -E 's/([][(){}.^$|*+?\\])/\\\\\1/g')
        # Extract the block from the new file (without the "key:" header)
        awk -v key="$key_re" '
          # When the exact block header is found, begin capture
          $0 ~ "^" key ":[[:space:]]*$" { flag = 1; next }
          # On the next top-level key, end capture
          /^[^[:space:]#][^:]*:[[:space:]]*/ { if (flag) { exit } }
          # While flag is active, print lines of the block
          flag { print }
        ' "$2" > "$TMP_DIR/block.new"

        if [ -s "$TMP_DIR/block.new" ]; then
          log_info "[textual-merge] block.new for '$key':"; sed -n '1,50p' "$TMP_DIR/block.new" 1>&2 || true
          log_info "[textual-merge] Found new nested lines for '$key', injecting if absent."
          # Insert missing lines from the new block just after the header in
          # the destination, avoiding duplicates and preserving order
          awk -v key="$key_re" -v tmpfile="$TMP_DIR/block.new" -v dest="$1" '
            # Build a set of all lines present in destination to avoid duplicates
            BEGIN {
              injected = 0
              while ((getline l < dest) > 0) { file_has[l] = 1 }
              close(dest)
            }
            # When hitting the target block header, mark that we are inside it
            $0 ~ "^" key ":[[:space:]]*$" { print; intarget = 1; next }
            # At the next top-level key, if still in block and not injected yet,
            # add only lines that are not already present
            /^[^[:space:]#][^:]*:[[:space:]]*/ {
              if (intarget && !injected) {
                while ((getline line < tmpfile) > 0) {
                  if (line != "" && !(line in file_has)) { print line }
                }
                close(tmpfile); injected = 1; intarget = 0
              }
            }
            # Default: print the current line unchanged
            { print }
            # If file ends while still inside block and not injected, insert pending lines
            END {
              if (intarget && !injected) {
                while ((getline line < tmpfile) > 0) {
                  if (line != "" && !(line in file_has)) { print line }
                }
                close(tmpfile)
              }
            }
          ' "$1" > "$TMP_DIR/target.tmp" 2>/dev/null || true
          if [ -s "$TMP_DIR/target.tmp" ]; then
            mv "$TMP_DIR/target.tmp" "$1"; ensure_permissions "$1"
            log_info "[textual-merge] Injected nested lines for '$key'."
          fi
        fi
      fi
    done < "$TMP_DIR/new_top_keys.txt"
    set -e || true
  fi
}

# merge_inline_flow_arrays
#   Special-case merge for top-level keys whose values are YAML flow-style
#   sequences (arrays written as "[a, b, c]") present in the new packaged file
#   and already present in the destination. The behavior appends only the
#   missing elements from the new array to the existing array, preserving the
#   original order of the destination and the appearance order from the new
#   file for appended elements. Other list styles (block lists with "- item")
#   are intentionally not handled here.
#
#   Args:
#     $1: destination file
#     $2: new packaged file
merge_inline_flow_arrays() {
  # Build a modified copy of destination with merged arrays.
  # Keys considered: any top-level line matching 'key: [ ... ]' in the new file.
  awk -v NEWFILE="$2" '
    function trim(s) { sub(/^([[:space:]]|\r)+/, "", s); sub(/([[:space:]]|\r)+$/, "", s); return s }
    function unquote(s) { s=trim(s); if (s ~ /^".*"$/) return substr(s, 2, length(s)-2); if (s ~ /^\x27.*\x27$/) return substr(s, 2, length(s)-2); return s }
    function starts_key_array(line, key_re,    m) {
      return (line ~ ("^" key_re ":[[:space:]]*\\["))
    }
    function escape_re(s,    t) {
      t=s; gsub(/([][(){}.^$|*+?\\])/ , "\\\\&", t); return t
    }
    function collect_keys_with_arrays(file,    l,k) {
      while ((getline l < file) > 0) {
        if (l ~ /^[^[:space:]#][^:]*:[[:space:]]*\[/) {
          k=l; sub(/:.*/, "", k); gsub(/[[:space:]]+$/, "", k);
          keys[++keysN] = k
        }
      }
      close(file)
    }
    function parse_array_for_key(file, key, rawA, normA,    l,cap,depth,buf,t,i,tok,n,key_re) {
      delete rawA; delete normA; rawA[0]=0
      key_re = escape_re(key)
      cap=0; depth=0; buf=""
      while ((getline l < file) > 0) {
        if (!cap) {
          if (starts_key_array(l, key_re)) {
            cap=1
            sub(/^[^\[]*\[/, "[", l)
            depth += gsub(/\[/, "[", l)
            depth -= gsub(/\]/, "]", l)
            sub(/^\[/, "", l)
            buf = buf l
            if (depth == 0) break
          }
        } else {
          depth += gsub(/\[/, "[", l)
          depth -= gsub(/\]/, "]", l)
          buf = buf l
          if (depth == 0) break
        }
      }
      close(file)
      sub(/].*$/, "", buf)
      n = split(buf, t, /,/)  # comma-separated tokens
      for (i=1; i<=n; i++) {
        tok = trim(t[i]); if (tok == "") continue
        rawA[++rawA[0]] = tok
        normA[unquote(tok)] = 1
      }
    }
    function build_merged_line(key, oldRaw, oldNorm, newRaw, newNorm,    out,i,norm) {
      out = key ": ["
      for (i=1; i<=oldRaw[0]; i++) {
        if (i>1) out = out ", "
        out = out oldRaw[i]
      }
      for (i=1; i<=newRaw[0]; i++) {
        norm = unquote(newRaw[i])
        if (!(norm in oldNorm)) {
          if (oldRaw[0] || appended_count) out = out ", "
          out = out newRaw[i]
          appended_count++
        }
      }
      out = out "]"
      return out
    }
    BEGIN {
      collect_keys_with_arrays(NEWFILE)
    }
    { lines[++N] = $0 }
    END {
      # Precompute replacements for each candidate key
      for (ki=1; ki<=keysN; ki++) {
        key = keys[ki]
        key_re = escape_re(key)
        # Locate range [start,end] in destination for this key
        start = end = 0
        for (i=1; i<=N; i++) {
          if (starts_key_array(lines[i], key_re)) { start = i; break }
        }
        if (!start) continue
        depth=0; tmp=lines[start]
        sub(/^[^\[]*\[/, "[", tmp)
        depth += gsub(/\[/, "[", tmp)
        depth -= gsub(/\]/, "]", tmp)
        if (depth == 0) { end = start } else {
          for (j=start+1; j<=N; j++) {
            tmp = lines[j]
            depth += gsub(/\[/, "[", tmp)
            depth -= gsub(/\]/, "]", tmp)
            if (depth == 0) { end = j; break }
          }
        }
        if (!end) continue

        # Parse arrays from dest and new
        delete oldRaw; delete oldNorm; oldRaw[0]=0
        delete newRaw; delete newNorm; newRaw[0]=0

        # Build dest buffer
        buf=""; tmp=lines[start]
        sub(/^[^\[]*\[/, "[", tmp); sub(/^\[/, "", tmp); buf = buf tmp
        for (j=start+1; j<=end; j++) buf = buf lines[j]
        sub(/].*$/, "", buf)
        n = split(buf, t, /,/) 
        for (i2=1; i2<=n; i2++) { tok = trim(t[i2]); if (tok=="") continue; oldRaw[++oldRaw[0]] = tok; oldNorm[unquote(tok)] = 1 }

        parse_array_for_key(NEWFILE, key, newRaw, newNorm)
        if (newRaw[0] == 0) continue

        repl[key] = build_merged_line(key, oldRaw, oldNorm, newRaw, newNorm)
        rstart[key] = start; rend[key] = end
      }

      # Print destination applying replacements
      i = 1
      while (i <= N) {
        replaced = 0
        for (ki=1; ki<=keysN; ki++) {
          key = keys[ki]
          if (i == rstart[key] && rend[key] > 0) {
            print repl[key]
            i = rend[key] + 1
            replaced = 1
            break
          }
        }
        if (!replaced) { print lines[i]; i++ }
      }
    }
  ' "$1" > "$TMP_DIR/arrays.merged.tmp" 2>/dev/null || true

  if [ -s "$TMP_DIR/arrays.merged.tmp" ]; then
    mv "$TMP_DIR/arrays.merged.tmp" "$1"
    ensure_permissions "$1"
    log_info "[array-merge] Merged inline flow arrays from packaged defaults."
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

# Backup the destination file before any modification
backup_config_file "$TARGET_PATH"

textual_additive_merge "$TARGET_PATH" "$NEW_PATH"

# Merge inline flow arrays (e.g., key: [a, b]) by appending missing elements
merge_inline_flow_arrays "$TARGET_PATH" "$NEW_PATH"

# Always remove the packaged new config file once handled (idempotent)
if [ -f "$NEW_PATH" ]; then
  rm -f "$NEW_PATH" || true
fi

exit 0
