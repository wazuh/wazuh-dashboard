#!/bin/sh
# Purpose: Merge new default settings from a packaged opensearch_dashboards.yml
# into the active /etc/wazuh-dashboard/opensearch_dashboards.yml, only adding
# keys that do not already exist. Performs a conservative, non-destructive
# merge: appends whole missing top-level blocks and injects only missing
# nested lines under existing blocks; never overwrites user-defined values.
#
# Special cases for lists:
# - Flow-style arrays (e.g., `key: [a, b]`) and block-style lists
#   (e.g., `key:` then indented `- a`) are merged by appending missing elements
#   from the new defaults while preserving the destination's existing order and
#   style. If styles differ between dest and new, the destination style is
#   preserved. This enables cases like
#   `plugins.security.system_indices.indices` where new indices must be added
#   without reordering or duplicating user-defined values.
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
    -v existing_keys_file="$TMP_DIR/existing_keys.txt" \
    -v added_keys_file="$ADDED_KEYS_FILE" \
    -v append_output_file="$APPEND_FILE" \
    '
    # Load current destination keys into destination_has_key[]
    BEGIN {
      while ((getline key_name < existing_keys_file) > 0) {
        destination_has_key[key_name] = 1
      }
      close(existing_keys_file)
    }

    # Buffer all lines from the new file for second pass
    {
      new_file_lines[NR] = $0
    }

    END {
      total_lines = NR

      # Detect top-level block starts and record their order
      for (i = 1; i <= total_lines; i++) {
        line = new_file_lines[i]
        # Skip comments and blank lines
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) {
          continue
        }
        # A top-level block starts at column 0 (non-space, non-#) and has ':'
        if (line ~ /^[^[:space:]#][^:]*:[[:space:]]*/) {
          key_name = line
          sub(/:.*/, "", key_name)            # Strip text after ':'
          gsub(/[[:space:]]+$/, "", key_name)  # Trim trailing spaces
          if (!(key_name in block_start_line)) {
            appearance_order[++appearance_count] = key_name   # Preserve appearance order
            block_start_line[key_name] = i                    # Record starting index
          }
        }
      }

      # Copy complete missing blocks (from start to next top-level or EOF)
      for (idx = 1; idx <= appearance_count; idx++) {
        current_key = appearance_order[idx]
        start_line = block_start_line[current_key]
        end_line = total_lines
        if (idx < appearance_count) {
          next_key = appearance_order[idx + 1]
          end_line = block_start_line[next_key] - 1
        }
        if (!(current_key in destination_has_key) && !(current_key in already_printed)) {
          for (j = start_line; j <= end_line; j++) {
            print new_file_lines[j] >> append_output_file   # Append block content
          }
          print current_key >> added_keys_file              # Record added key
          already_printed[current_key] = 1
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
    while IFS= read -r top_level_key; do
      # Only process keys that exist in destination as well
      if grep -q "^${top_level_key}:[[:space:]]*" "$1"; then
        log_info "[textual-merge] Processing existing top-level key: $top_level_key"
        target_key_regex=$(printf '%s' "$top_level_key" | sed -E 's/([][(){}.^$|*+?\\])/\\\\\1/g')
        # Extract the block from the new file (without the "key:" header)
        awk -v target_key_regex="$target_key_regex" '
          # When the exact block header is found, begin capture
          $0 ~ "^" target_key_regex ":[[:space:]]*$" { capture = 1; next }
          # On the next top-level key, end capture
          /^[^[:space:]#][^:]*:[[:space:]]*/ { if (capture) { exit } }
          # While capture is active, print lines of the block
          capture { print }
        ' "$2" > "$TMP_DIR/block.new"

        if [ -s "$TMP_DIR/block.new" ]; then
          log_info "[textual-merge] block.new for '$top_level_key':"; sed -n '1,50p' "$TMP_DIR/block.new" 1>&2 || true
          log_info "[textual-merge] Found new nested lines for '$top_level_key', injecting if absent."
          # Insert missing lines from the new block just after the header in
          # the destination, avoiding duplicates and preserving order
          awk -v target_key_regex="$target_key_regex" -v new_block_path="$TMP_DIR/block.new" -v destination_path="$1" '
            # Build a set of all lines present in destination to avoid duplicates
            BEGIN {
              injected_already = 0
              while ((getline destination_line < destination_path) > 0) { destination_line_set[destination_line] = 1 }
              close(destination_path)
            }
            # When hitting the target block header, mark that we are inside it
            $0 ~ "^" target_key_regex ":[[:space:]]*$" { print; inside_target_block = 1; next }
            # At the next top-level key, if still in block and not injected yet,
            # add only lines that are not already present
            /^[^[:space:]#][^:]*:[[:space:]]*/ {
              if (inside_target_block && !injected_already) {
                while ((getline new_block_line < new_block_path) > 0) {
                  if (new_block_line != "" && !(new_block_line in destination_line_set)) { print new_block_line }
                }
                close(new_block_path); injected_already = 1; inside_target_block = 0
              }
            }
            # Default: print the current line unchanged
            { print }
            # If file ends while still inside block and not injected, insert pending lines
            END {
              if (inside_target_block && !injected_already) {
                while ((getline new_block_line < new_block_path) > 0) {
                  if (new_block_line != "" && !(new_block_line in destination_line_set)) { print new_block_line }
                }
                close(new_block_path)
              }
            }
          ' "$1" > "$TMP_DIR/target.tmp" 2>/dev/null || true
          if [ -s "$TMP_DIR/target.tmp" ]; then
            mv "$TMP_DIR/target.tmp" "$1"; ensure_permissions "$1"
            log_info "[textual-merge] Injected nested lines for '$top_level_key'."
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
  # Keys considered: any top-level key present in the new file. If the
  # destination uses flow-style for that key, merge items from the new file
  # regardless of whether the new file uses flow or block style.
  awk -v NEWFILE="$2" '
    function trim(s) { sub(/^([[:space:]]|\r)+/, "", s); sub(/([[:space:]]|\r)+$/, "", s); return s }
    function unquote(s) { s=trim(s); if (s ~ /^".*"$/) return substr(s, 2, length(s)-2); if (s ~ /^\x27.*\x27$/) return substr(s, 2, length(s)-2); return s }
    function starts_key_array(line, key_re,    m) {
      return (line ~ ("^" key_re ":[[:space:]]*\\["))
    }
    function escape_re(s,    t) {
      t=s; gsub(/([][(){}.^$|*+?\\])/ , "\\\\&", t); return t
    }
    function collect_top_keys(file, line, key_name) {
      while ((getline line < file) > 0) {
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
        if (line ~ /^[^[:space:]#][^:]*:/) {
          key_name=line; sub(/:.*/, "", key_name); gsub(/[[:space:]]+$/, "", key_name);
          keys[++keysN] = key_name
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
    function parse_block_for_key(file, key, rawA, normA,    l,cap,buf,key_re,depth,lines,N,i,mt) {
      delete rawA; delete normA; rawA[0]=0
      key_re = escape_re(key)
      N=0; while((getline l < file)>0){ lines[++N]=l } close(file)
      # find header strictly 'key:'
      s=0; for(i=1;i<=N;i++){ if(lines[i] ~ ("^" key_re ":[[:space:]]*$")){ s=i; break } }
      if(!s) return
      # ensure next non-empty/comment starts with '-'
      isBlock=0; for(i=s+1;i<=N;i++){ if(lines[i] ~ /^[[:space:]]*#/ || lines[i] ~ /^[[:space:]]*$/) continue; if(lines[i] ~ /^[[:space:]]*-\s+/){ isBlock=1; break } else { break } }
      if(!isBlock) return
      # read until next top key
      e=N; for(i=s+1;i<=N;i++){ if(lines[i] ~ /^[^[:space:]#][^:]*:[[:space:]]*/){ e=i-1; break } }
      for(i=s+1;i<=e;i++){ l=lines[i]; if(l ~ /^[[:space:]]*#/ || l ~ /^[[:space:]]*$/) continue; if(match(l,/^([[:space:]]*)-\s*(.*)$/,mt)){ tok=mt[2]; rawA[++rawA[0]]=tok; normA[unquote(tok)]=1 } }
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
    BEGIN { collect_top_keys(NEWFILE) }
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

        # Parse arrays from dest and new (new may be flow or block)
        delete oldRaw; delete oldNorm; oldRaw[0]=0
        delete newRaw; delete newNorm; newRaw[0]=0

        # Build dest buffer
        buf=""; tmp=lines[start]
        sub(/^[^\[]*\[/, "[", tmp); sub(/^\[/, "", tmp); buf = buf tmp
        for (j=start+1; j<=end; j++) buf = buf lines[j]
        sub(/].*$/, "", buf)
        n = split(buf, t, /,/)
        for (i2=1; i2<=n; i2++) { tok = trim(t[i2]); if (tok=="") continue; oldRaw[++oldRaw[0]] = tok; oldNorm[unquote(tok)] = 1 }
        # Try flow-style in new first
        parse_array_for_key(NEWFILE, key, newRaw, newNorm)
        if (newRaw[0] == 0) { parse_block_for_key(NEWFILE, key, newRaw, newNorm) }
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

# merge_top_level_lists_preserve_style
#   General list merge for top-level keys when either file uses list syntax
#   (flow `[...]` or block `- item`). Style is preserved from destination.
#
#   Args:
#     $1: destination file
#     $2: new packaged file
merge_top_level_lists_preserve_style() {
  awk -v NEWFILE="$2" '
    function trim(s){ sub(/^([[:space:]]|\r)+/,"",s); sub(/([[:space:]]|\r)+$/,"",s); return s }
    function unquote(s){ s=trim(s); if(s ~ /^".*"$/) return substr(s,2,length(s)-2); if(s ~ /^\x27.*\x27$/) return substr(s,2,length(s)-2); return s }
    function esc(s){ t=s; gsub(/([][(){}.^$|*+?\\])/ , "\\\\&", t); return t }
    function starts_top_key(line, key_re){ return (line ~ ("^" key_re ":[[:space:]]*")) }
    function is_top_key_line(line){ return (line ~ /^[^[:space:]#][^:]*:[[:space:]]*/) }
    function parse_flow_items_from_buffer(buf, rawA, normA,    t,i,tok){ delete rawA; delete normA; rawA[0]=0; sub(/^[^\[]*\[/,"[",buf); sub(/^\[/, "", buf); sub(/].*$/, "", buf); n=split(buf,t,/,/); for(i=1;i<=n;i++){ tok=trim(t[i]); if(tok!=""){ rawA[++rawA[0]]=tok; normA[unquote(tok)]=1 } } }
    function collect_block_items(lines, N, start, end, rawA, normA,    i,ind,cap,l,mtch){ delete rawA; delete normA; rawA[0]=0; ind=""; cap=0; for(i=start+1;i<=end;i++){ l=lines[i]; if(l ~ /^[[:space:]]*#/ || l ~ /^[[:space:]]*$/) { continue } if(match(l, /^([[:space:]]*)-\s*(.*)$/, mtch)){ if(ind=="") ind=mtch[1]; tok=mtch[2]; rawA[++rawA[0]]=tok; normA[unquote(tok)]=1; cap=1 } else if(cap && is_top_key_line(l)) { break } }
      return ind }
    function find_block(lines, N, key, style, sidx, eidx,    i,key_re,l,depth,tmp){ key_re=esc(key); style="none"; sidx=0; eidx=0; for(i=1;i<=N;i++){ l=lines[i]; if(starts_top_key(l,key_re)){ sidx=i; break } } if(!sidx){ return 0 }
      # Detect flow vs block
      if(lines[sidx] ~ /\[[^\]]*$/){ style="flow"; depth=0; tmp=lines[sidx]; sub(/^[^\[]*\[/,"[",tmp); depth += gsub(/\[/,"[",tmp); depth -= gsub(/\]/,"]",tmp); if(depth==0){ eidx=sidx } else { for(i=sidx+1;i<=N;i++){ tmp=lines[i]; depth += gsub(/\[/,"[",tmp); depth -= gsub(/\]/,"]",tmp); if(depth==0){ eidx=i; break } } } }
      else {
        # If next non-empty/comment line starts with dash, consider block list; otherwise treat as scalar
        for(i=sidx+1;i<=N;i++){ l=lines[i]; if(l ~ /^[[:space:]]*#/ || l ~ /^[[:space:]]*$/) continue; if(l ~ /^[[:space:]]*-\s+/){ style="block"; break } else { style="scalar"; break } }
        if(style=="block"){ # end at next top-level key or EOF
          eidx=N; for(i=sidx+1;i<=N;i++){ if(is_top_key_line(lines[i])){ eidx=i-1; break } }
        }
      }
      if(eidx==0) eidx=sidx; return 1 }
    function parse_items(lines,N,start,end,style,rawA,normA,indent,    buf){ if(style=="flow"){ buf=""; for(i=start;i<=end;i++) buf = buf lines[i]; parse_flow_items_from_buffer(buf,rawA,normA) ; indent="" } else if(style=="block"){ indent = collect_block_items(lines,N,start,end,rawA,normA) } else { delete rawA; delete normA; rawA[0]=0; indent="" } return indent }
    function parse_items_from_file(file, key, rawA, normA, style, indent,    lns,Nl,ok,s,e){ Nl=0; while((getline l < file)>0){ lns[++Nl]=l } close(file); ok=find_block(lns,Nl,key,style,s,e); if(!ok){ style="none"; indent=""; rawA[0]=0; return 0 } indent=parse_items(lns,Nl,s,e,style,rawA,normA,indent); return 1 }
    function build_flow_line(key, oldRaw, oldNorm, newRaw,    out,i,norm){ out=key ": ["; for(i=1;i<=oldRaw[0];i++){ if(i>1) out=out ", "; out=out oldRaw[i] } for(i=1;i<=newRaw[0];i++){ norm=unquote(newRaw[i]); if(!(norm in oldNorm)){ if(oldRaw[0]>0 || appended) out=out ", "; out=out newRaw[i]; appended++ } } out=out "]"; return out }
    function build_block_lines(key, lines, N, start, end, newRaw, oldNorm, indent,    i,buf){ for(i=1;i<=N;i++){ out_lines[++outN]=lines[i] } # placeholder; handled later
      return 1 }

    { dst[++DN]=$0 }
    END {
      # Load new file lines
      while((getline nl < NEWFILE)>0){ src[++SN]=nl } close(NEWFILE)

      # Iterate over top-level keys in new file
      # First, collect their order
      for(i=1;i<=SN;i++){
        l=src[i]; if(l ~ /^[[:space:]]*#/ || l ~ /^[[:space:]]*$/) continue
        if(match(l,/^[^[:space:]#][^:]*:/)){
          k=l; sub(/:.*/,"",k); gsub(/[[:space:]]+$/,"",k); if(!(k in seen)){ order[++orderN]=k; seen[k]=1 }
        }
      }

      # Prepare a mapping from index to replacement for destination
      for(oi=1; oi<=orderN; oi++){
        key=order[oi]
        # Parse items from new (if any list)
        if(!parse_items_from_file(NEWFILE, key, newRaw, newNorm, newStyle, newIndent)) continue
        if(newStyle!="flow" && newStyle!="block") continue

        # Parse destination block and style; skip if key not present in dest
        if(!find_block(dst, DN, key, dstStyle, s, e)) continue
        if(dstStyle=="scalar") continue

        # Parse destination items
        indent = parse_items(dst, DN, s, e, dstStyle, oldRaw, oldNorm, indent)

        # Build replacement respecting destination style
        if(dstStyle=="flow"){
          repl = build_flow_line(key, oldRaw, oldNorm, newRaw)
          RSTART[s] = 1; REND[s] = e; RLINE[s] = repl
        } else if(dstStyle=="block"){
          # Reconstruct: print header and original body, then append missing items as new lines
          # Determine indent (default two spaces if none found)
          ind = indent; if(ind=="") ind="  "
          # Prepare list of append lines
          append_lines_count=0
          for(i=1;i<=newRaw[0];i++){
            norm = unquote(newRaw[i]); if(!(norm in oldNorm)){ append_lines[++append_lines_count] = ind "- " newRaw[i] }
          }
          if(append_lines_count>0){
            # Store replacement as header + original block + appended items
            # Capture header
            header = dst[s]
            body=""; for(i=s+1;i<=e;i++){ body = body dst[i] "\n" }
            repl_block = header "\n" body
            for(i=1;i<=append_lines_count;i++){ repl_block = repl_block append_lines[i] "\n" }
            # Trim trailing newline from repl_block when printing
            RSTART[s] = 1; REND[s] = e; RBLK[s] = repl_block
          }
        }
      }

      # Emit destination with replacements
      i=1
      while(i<=DN){
        if(RSTART[i]){
          if(RLINE[i] != ""){
            print RLINE[i]
          } else if(RBLK[i] != ""){
            sub(/\n$/,"",RBLK[i]); print RBLK[i]
          }
          i = REND[i] + 1
        } else {
          print dst[i]; i++
        }
      }
    }
  ' "$1" > "$TMP_DIR/lists.merged.tmp" 2>/dev/null || true

  if [ -s "$TMP_DIR/lists.merged.tmp" ]; then
    mv "$TMP_DIR/lists.merged.tmp" "$1"
    ensure_permissions "$1"
    log_info "[list-merge] Merged top-level lists preserving destination style."
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

# Merge flow-style arrays first (handles flow and mixed where dest is flow)
merge_inline_flow_arrays "$TARGET_PATH" "$NEW_PATH"

# Merge block-style lists where destination already uses '-' style
merge_block_lists_preserve_style() {
  awk -v NEWFILE="$2" '
    function trim(s){ sub(/^([[:space:]]|\r)+/,"",s); sub(/([[:space:]]|\r)+$/,"",s); return s }
    function unquote(s){ s=trim(s); if(s ~ /^".*"$/) return substr(s,2,length(s)-2); if(s ~ /^\x27.*\x27$/) return substr(s,2,length(s)-2); return s }
    function esc(s){ t=s; gsub(/([][(){}.^$|*+?\\])/ , "\\\\&", t); return t }
    function is_top_key_line(line){ return (line ~ /^[^[:space:]#][^:]*:[[:space:]]*/) }
    function parse_block_items(lines,N,start,end,rawA,normA,indent,    i,l,mt){ delete rawA; delete normA; rawA[0]=0; indent=""; for(i=start+1;i<=end;i++){ l=lines[i]; if(l ~ /^[[:space:]]*#/ || l ~ /^[[:space:]]*$/) continue; if(match(l,/^([[:space:]]*)-\s*(.*)$/,mt)){ if(indent=="") indent=mt[1]; tok=mt[2]; rawA[++rawA[0]]=tok; normA[unquote(tok)]=1 } else if(is_top_key_line(l)) { break } } return indent }
    function find_dest_block_lists(lines,N,    i,l,k,m){ for(i=1;i<=N;i++){ l=lines[i]; if(match(l,/^([^[:space:]#][^:]*):[[:space:]]*$/,m)){ k=m[1]; # look ahead for dash
          for(j=i+1;j<=N;j++){ if(lines[j] ~ /^[[:space:]]*#/ || lines[j] ~ /^[[:space:]]*$/) continue; if(lines[j] ~ /^[[:space:]]*-\s+/){ d_start[k]=i; # end at next top key
              e=i; for(m=i+1;m<=N;m++){ if(is_top_key_line(lines[m])){ e=m-1; break } } d_end[k]=e; break } else { break } } } } }
    function parse_new_items_any_style(src,SN,key,rawA,normA,    i,l,keyre,cap,depth,buf,t,n,tok,s,e){ delete rawA; delete normA; rawA[0]=0; keyre=esc(key)
      # Try block style first
      s=0; for(i=1;i<=SN;i++){ if(src[i] ~ ("^" keyre ":[[:space:]]*$")){ s=i; break } }
      if(s){ for(i=s+1;i<=SN;i++){ if(src[i] ~ /^[[:space:]]*#/ || src[i] ~ /^[[:space:]]*$/) continue; if(src[i] ~ /^[[:space:]]*-\s+/){ # block
              e=SN; for(m=s+1;m<=SN;m++){ if(is_top_key_line(src[m])){ e=m-1; break } }
              # collect block items
              for(m=s+1;m<=e;m++){ l=src[m]; if(l ~ /^[[:space:]]*#/ || l ~ /^[[:space:]]*$/) continue; if(match(l,/^([[:space:]]*)-\s*(.*)$/,t)){ tok=t[2]; rawA[++rawA[0]]=tok; normA[unquote(tok)]=1 } } return 1 } else { break } } }
      # Try flow style
      cap=0; depth=0; buf=""; for(i=1;i<=SN;i++){ l=src[i]; if(!cap){ if(l ~ ("^" keyre ":[[:space:]]*\\[")){ cap=1; sub(/^[^\[]*\[/,"[",l); depth+=gsub(/\[/,"[",l); depth-=gsub(/\]/,"]",l); sub(/^\[/,"",l); buf=buf l; if(depth==0) break } } else { depth+=gsub(/\[/,"[",l); depth-=gsub(/\]/,"]",l); buf=buf l; if(depth==0) break } } sub(/].*$/,"",buf); if(buf!=""){ n=split(buf,t,/,/); for(i=1;i<=n;i++){ tok=trim(t[i]); if(tok!=""){ rawA[++rawA[0]]=tok; normA[unquote(tok)]=1 } } return 1 }
      return 0 }
    { dst[++DN]=$0 }
    END {
      while((getline nl < NEWFILE)>0){ src[++SN]=nl } close(NEWFILE)
      # Index destination block lists
      find_dest_block_lists(dst,DN)
      # For each recorded dest block list key, parse items and merge
      for (key in d_start){ sD=d_start[key]; eD=d_end[key]; if(sD==0||eD==0) continue; # parse dest
        destIndent = parse_block_items(dst,DN,sD,eD,oldRaw,oldNorm,destIndent); if(destIndent=="") destIndent="  "
        # parse new items any style
        if(!parse_new_items_any_style(src,SN,key,newRaw,newNorm)) continue
        append_count=0; for(i=1;i<=newRaw[0];i++){ nm=unquote(newRaw[i]); if(!(nm in oldNorm)){ append[++append_count] = destIndent "- " newRaw[i] } }
        if(append_count>0){ header=dst[sD]; body=""; for(i=sD+1;i<=eD;i++){ body = body dst[i] "\n" } repl = header "\n" body; for(i=1;i<=append_count;i++){ repl = repl append[i] "\n" } RSTART[sD]=1; REND[sD]=eD; RBLK[sD]=repl }
      }
      # Emit destination with replacements
      i=1; while(i<=DN){ if(RSTART[i]){ sub(/\n$/,"",RBLK[i]); print RBLK[i]; i=REND[i]+1 } else { print dst[i]; i++ } }
    }
  ' "$1" > "$TMP_DIR/blocklists.merged.tmp" 2>/dev/null || true
  if [ -s "$TMP_DIR/blocklists.merged.tmp" ]; then
    mv "$TMP_DIR/blocklists.merged.tmp" "$1"
    ensure_permissions "$1"
    log_info "[list-merge] Merged block-style lists preserving '-' style."
  fi
}

merge_block_lists_preserve_style "$TARGET_PATH" "$NEW_PATH"

# Handle mixed style: destination uses block list ('-') and new file provides
# a flow-style array. We synthesize a minimal YAML with only the missing
# elements under the corresponding block keys and reuse the textual additive
# injector to append them.
merge_flow_to_block_via_textual() {
  BLOCK_INJECTIONS_FILE="$TMP_DIR/block_injections.yml"
  : > "$BLOCK_INJECTIONS_FILE"
  awk -v DEST_PATH="$1" -v SRC_PATH="$2" -v OUTPUT_PATH="$BLOCK_INJECTIONS_FILE" '
    function trim(text){ sub(/^([[:space:]]|\r)+/,"",text); sub(/([[:space:]]|\r)+$/,"",text); return text }
    function escape_regex(text){ gsub(/([][(){}.^$|*+?\\])/ , "\\\\&", text); return text }
    # Load destination block-list keys
    BEGIN {
      while((getline dest_line < DEST_PATH)>0){ dest_lines[++dest_count]=dest_line }
      close(DEST_PATH)
      for(i=1;i<=dest_count;i++){
        line=dest_lines[i]
        if(match(line,/^([^[:space:]#][^:]*):[[:space:]]*$/,m)){
          key_name=m[1]
          # check next significant line starts with dash
          for(j=i+1;j<=dest_count;j++){
            if(dest_lines[j] ~ /^[[:space:]]*#/ || dest_lines[j] ~ /^[[:space:]]*$/) continue
            if(dest_lines[j] ~ /^[[:space:]]*-\s+/){ is_block_key[key_name]=1 }
            break
          }
        }
      }
      # Parse flow arrays from SRC and emit blocks for keys that are block in DEST
      while((getline src_line < SRC_PATH)>0){ src_lines[++src_count]=src_line }
      close(SRC_PATH)
      for(i=1;i<=src_count;i++){
        line=src_lines[i]
        if(match(line,/^([^[:space:]#][^:]*):[[:space:]]*\[/,m)){
          key_name=m[1]
          if(!(key_name in is_block_key)) continue
          # capture until closing ]
          buffer=line; depth=gsub(/\[/,"[",line)-gsub(/\]/,"]",line)
          while(depth>0 && i<src_count){ i++; ln=src_lines[i]; buffer=buffer ln; depth+=gsub(/\[/,"[",ln)-gsub(/\]/,"]",ln) }
          sub(/^[^\[]*\[/,"[",buffer); sub(/^\[/, "", buffer); sub(/].*$/, "", buffer)
          tokens_count=split(buffer, tokens, /,/)
          if(tokens_count>0){
            print key_name ":" >> OUTPUT_PATH
            for(k=1;k<=tokens_count;k++){ token=trim(tokens[k]); if(token!="") print "  - " token >> OUTPUT_PATH }
          }
        }
      }
    }
  ' /dev/null
  if [ -s "$BLOCK_INJECTIONS_FILE" ]; then
    # Reuse textual additive merger to append only missing lines under blocks
    BLOCKIFIED_NEW_FILE="$TMP_DIR/new.blockified.yml"
    cp "$BLOCK_INJECTIONS_FILE" "$BLOCKIFIED_NEW_FILE"
    textual_additive_merge "$TARGET_PATH" "$BLOCKIFIED_NEW_FILE"
  fi
}

merge_flow_to_block_via_textual "$TARGET_PATH" "$NEW_PATH"

# Always remove the packaged new config file once handled (idempotent)
if [ -f "$NEW_PATH" ]; then
  rm -f "$NEW_PATH" || true
fi

exit 0
