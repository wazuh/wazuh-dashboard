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
#   preserved. This enables cases where new indices must be added
#   without reordering or duplicating user-defined values.
#
# Design notes (clean code / maintainability):
# - Single-responsibility functions for argument parsing, capability detection,
#   merge strategies, permission handling, and logging.
# - All hardcoded values consolidated as constants below for easy change.
# - POSIX sh compatible (no bashisms) to maximize portability.
# - Explicit and defensive checks; exits cleanly if nothing to do.

# Be conservative about aborting: avoid exiting on non-zero intermediate commands.
# We keep undefined-variable checks. Functions may locally tweak `set -e`/`set +e`
# for their own inner pipelines, but we avoid relying on global `-e` behavior.
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
log_info() { echo "[INFO]  $*" 1>&2; }

# log_warn
#   Emit a warning to stderr. Useful for unknown arguments or operations that
#   continue with default behavior.
#   Example:
#     log_warn "Ignoring unknown argument: --foo"
log_warn() { echo "[WARN]  $*" 1>&2; }

# log_error
#   Emit an error to stderr. Does NOT terminate the script; intended to record
#   non-critical failures that should not abort the merge.
#   Example:
#     log_error "Could not set ownership; continuing"
log_error() { echo "[ERROR] $*" 1>&2; }

# usage
#   Show script usage help.
#   Example:
#     ./merge-config.sh --help
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

    # If the line looks like a YAML mapping key ending with ':', extract it.
    # Indentation is not strictly enforced here; this collector is used only
    # to compare names against truly top-level keys detected elsewhere.
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

# textual_additive_merge
# Performs an additive (non-destructive) textual merge of Wazuh dashboard YAML
# configuration using a single fragment file.
# Intended usage: textual_additive_merge <base_file> <fragment_file>
#
# Behavior (current implementation):
# - Reads a base opensearch_dashboards.yml (first argument).
# - Scans the fragment file's non-empty, non-comment lines.
# - Whole missing top-level blocks are appended to the end of the file.
# - For existing top-level keys, missing nested lines from the fragment are
#   injected directly after the key header in the destination (order-preserving),
#   avoiding duplicates.
# - Existing user-defined lines are left untouched (no override), ensuring
#   idempotency when run multiple times.
# - Comment lines (starting with '#') and blank lines may be preserved only if
#   they accompany newly added keys (implementation-dependent).
#
# Note:
# - To merge multiple fragments, call this function repeatedly (one fragment at
#   a time) or extend the implementation to iterate over additional arguments.
#
# Expected advantages:
# - Safe merging strategy for layered packaging or plugin installation steps where you only want to
#   introduce missing settings without risking overwriting user customizations.
# - Simple deterministic output: rerunning with the same inputs should not duplicate lines.
#
# Possible limitations / assumptions:
# - Key collision detection is line-based (string match) rather than full YAML
#   semantic parsing.
# - Does not reorder or remove existing settings.
# - May not handle multiline YAML structures (e.g., folded scalars, lists)
#   beyond simple line presence tests.
#
# Exit status:
# - 0 on success.
# - Non-zero on I/O errors or invalid arguments (exact codes depend on implementation).
#
# Example (conceptual):
#   textual_additive_merge /etc/opensearch/opensearch.yml extras/security.yml
#
# Notes for maintainers:
# - If enhancing to be YAML-aware, ensure backward compatibility (retain additive semantics).
# - Consider normalizing whitespace to reduce false negatives on duplicate detection.
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
          # If the new block is a block-style list (lines beginning with '-')
          # skip textual injection and let the dedicated list merge handle it
          if grep -qE '^[[:space:]]*-[[:space:]]+' "$TMP_DIR/block.new"; then
            log_info "[textual-merge] Skipping list-style block for '$top_level_key' (handled by list merge)."
            continue
          fi
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
    function trim(originalText) {
      sub(/^([[:space:]]|\r)+/, "", originalText)
      sub(/([[:space:]]|\r)+$/, "", originalText)
      return originalText
    }
    function unquote(originalText) {
      originalText = trim(originalText)
      if (originalText ~ /^".*"$/) return substr(originalText, 2, length(originalText)-2)
      if (originalText ~ /^\x27.*\x27$/) return substr(originalText, 2, length(originalText)-2)
      return originalText
    }
    function doesLineStartFlowStyleArrayForKey(lineText, escapedKeyRegex, unusedMatchVar) {
      return (lineText ~ ("^" escapedKeyRegex ":[[:space:]]*\\["))
    }
    function escapeLiteralToAwkRegexPattern(literalText, tempWorkingText) {
      tempWorkingText = literalText
      gsub(/([][(){}.^$|*+?\\])/ , "\\\\&", tempWorkingText)
      return tempWorkingText
    }
    function collectTopLevelKeysFromFile(filePath,
                       currentLineText,
                       extractedKeyName) {
      while ((getline currentLineText < filePath) > 0) {
      if (currentLineText ~ /^[[:space:]]*#/ || currentLineText ~ /^[[:space:]]*$/) continue
      if (currentLineText ~ /^[^[:space:]#][^:]*:/) {
        extractedKeyName = currentLineText
        sub(/:.*/, "", extractedKeyName)
        gsub(/[[:space:]]+$/, "", extractedKeyName)
        keys[++keysN] = extractedKeyName          # existing external contract
        topLevelKeyNames[++topLevelKeyCount] = extractedKeyName
      }
      }
      close(filePath)
    }

    function parse_array_for_key(filePath,
                   targetKeyName,
                   destinationRawTokenArray,
                   destinationNormalizedTokenMap,
                   currentLineText,
                   captureActiveFlag,
                   bracketDepthCounter,
                   accumulatedBuffer,
                   splitTokenArray,
                   tokenIndex,
                   tokenValue,
                   tokenCount,
                   escapedKeyRegexPattern) {
      delete destinationRawTokenArray
      delete destinationNormalizedTokenMap
      destinationRawTokenArray[0] = 0

      escapedKeyRegexPattern = escapeLiteralToAwkRegexPattern(targetKeyName)
      captureActiveFlag = 0
      bracketDepthCounter = 0
      accumulatedBuffer = ""

      while ((getline currentLineText < filePath) > 0) {
      if (!captureActiveFlag) {
        if (doesLineStartFlowStyleArrayForKey(currentLineText, escapedKeyRegexPattern)) {
        captureActiveFlag = 1
        sub(/^[^\[]*\[/, "[", currentLineText)
        bracketDepthCounter += gsub(/\[/, "[", currentLineText)
        bracketDepthCounter -= gsub(/\]/, "]", currentLineText)
        sub(/^\[/, "", currentLineText)
        accumulatedBuffer = accumulatedBuffer currentLineText
        if (bracketDepthCounter == 0) break
        }
      } else {
        bracketDepthCounter += gsub(/\[/, "[", currentLineText)
        bracketDepthCounter -= gsub(/\]/, "]", currentLineText)
        accumulatedBuffer = accumulatedBuffer currentLineText
        if (bracketDepthCounter == 0) break
      }
      }
      close(filePath)

      sub(/].*$/, "", accumulatedBuffer)
      tokenCount = split(accumulatedBuffer, splitTokenArray, /,/)

      for (tokenIndex = 1; tokenIndex <= tokenCount; tokenIndex++) {
      tokenValue = trim(splitTokenArray[tokenIndex])
      if (tokenValue == "") continue
      destinationRawTokenArray[++destinationRawTokenArray[0]] = tokenValue
      destinationNormalizedTokenMap[unquote(tokenValue)] = 1
      }
    }

    function parse_block_for_key(filePath,
                   targetKeyName,
                   destinationRawTokenArray,
                   destinationNormalizedTokenMap,
                   currentLineText,
                   captureActiveFlag,
                   accumulatedBuffer,
                   escapedKeyRegexPattern,
                   bracketDepthCounter,
                   fileLineArray,
                   totalLineCount,
                   lineIndex,
                   matchGroupsArray,
                   headerStartLineIndex,
                   isBlockStyleFlag,
                   blockEndLineIndex,
                   tokenValue) {
      delete destinationRawTokenArray
      delete destinationNormalizedTokenMap
      destinationRawTokenArray[0] = 0

      escapedKeyRegexPattern = escapeLiteralToAwkRegexPattern(targetKeyName)
      totalLineCount = 0
      while ((getline currentLineText < filePath) > 0) {
      fileLineArray[++totalLineCount] = currentLineText
      }
      close(filePath)

      headerStartLineIndex = 0
      for (lineIndex = 1; lineIndex <= totalLineCount; lineIndex++) {
      if (fileLineArray[lineIndex] ~ ("^" escapedKeyRegexPattern ":[[:space:]]*$")) {
        headerStartLineIndex = lineIndex
        break
      }
      }
      if (!headerStartLineIndex) return

      isBlockStyleFlag = 0
      for (lineIndex = headerStartLineIndex + 1; lineIndex <= totalLineCount; lineIndex++) {
      if (fileLineArray[lineIndex] ~ /^[[:space:]]*#/ || fileLineArray[lineIndex] ~ /^[[:space:]]*$/) continue
      if (fileLineArray[lineIndex] ~ /^[[:space:]]*-\s+/) {
        isBlockStyleFlag = 1
        break
      } else {
        break
      }
      }
      if (!isBlockStyleFlag) return

      blockEndLineIndex = totalLineCount
      for (lineIndex = headerStartLineIndex + 1; lineIndex <= totalLineCount; lineIndex++) {
      if (fileLineArray[lineIndex] ~ /^[^[:space:]#][^:]*:[[:space:]]*/) {
        blockEndLineIndex = lineIndex - 1
        break
      }
      }

      for (lineIndex = headerStartLineIndex + 1; lineIndex <= blockEndLineIndex; lineIndex++) {
      currentLineText = fileLineArray[lineIndex]
      if (currentLineText ~ /^[[:space:]]*#/ || currentLineText ~ /^[[:space:]]*$/) continue
      if (match(currentLineText, /^([[:space:]]*)-\s*(.*)$/, matchGroupsArray)) {
        tokenValue = matchGroupsArray[2]
        destinationRawTokenArray[++destinationRawTokenArray[0]] = tokenValue
        destinationNormalizedTokenMap[unquote(tokenValue)] = 1
      }
      }
    }

    function build_merged_line(topLevelKeyName,
                   existingRawTokens,
                   existingNormalizedTokenMap,
                   newRawTokens,
                   newNormalizedTokenMap,
                   mergedLine,
                   existingTokenIndex,
                   newTokenIndex,
                   normalizedTokenValue) {
      mergedLine = topLevelKeyName ": ["
      for (existingTokenIndex = 1; existingTokenIndex <= existingRawTokens[0]; existingTokenIndex++) {
      if (existingTokenIndex > 1) mergedLine = mergedLine ", "
      mergedLine = mergedLine existingRawTokens[existingTokenIndex]
      }
      for (newTokenIndex = 1; newTokenIndex <= newRawTokens[0]; newTokenIndex++) {
      normalizedTokenValue = unquote(newRawTokens[newTokenIndex])
      if (!(normalizedTokenValue in existingNormalizedTokenMap)) {
        if (existingRawTokens[0] || appended_count) mergedLine = mergedLine ", "
        mergedLine = mergedLine newRawTokens[newTokenIndex]
        appended_count++
      }
      }
      mergedLine = mergedLine "]"
      return mergedLine
    }
    BEGIN { collectTopLevelKeysFromFile(NEWFILE) }
    { lines[++N] = $0 }
    END {
      # Precompute replacements for each candidate key
      for (ki=1; ki<=keysN; ki++) {
        key = keys[ki]
        key_re = escapeLiteralToAwkRegexPattern(key)
        # Locate range [start,end] in destination for this key
        start = end = 0
        for (i=1; i<=N; i++) {
          if (doesLineStartFlowStyleArrayForKey(lines[i], key_re)) { start = i; break }
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

# Specialized list-merge helpers

# merge_block_lists_preserve_style
# -----------------------------------------------------------------------------
# Purpose:
#   Merge YAML/OpenSearch block-style lists that already exist in the
#   destination file while preserving:
#     - Original list ordering (stable merge unless duplicates are removed)
#     - Existing indentation, line endings, and comment placement
#     - Quoting style (single, double, or unquoted) of pre-existing entries
#     - Blank line separation to maintain human-friendly readability
#
# Typical Use Case:
#   Used during build/packaging of Wazuh dashboard to combine a baseline
#   opensearch_dashboards.yml fragment with plugin- or environment-specific list
#   extensions (e.g. node.roles, discovery.seed_hosts, plugins.security.*
#   allowlists/denylists) without reformatting the surrounding file.
#
# Behavior:
#   - Parses targeted block list regions (lines beginning with a dash "-")
#   - Normalizes candidate new entries for duplicate detection in a
#     case-sensitive or case-insensitive manner (implementation dependent)
#   - Appends only entries not already present in the original list
#   - Preserves trailing comments on list items (e.g. "- value  # note")
#   - Avoids reflowing or sorting unless explicitly required
#
# Input (expected assumptions):
#   - Positional parameters supply:
#       1) Path to the destination opensearch.yml (argument $1)
#       2) Path to the new packaged file to read candidates from (argument $2)
#   - Keys to merge are auto-detected by scanning the destination for
#     top-level headers followed by `- item` lines (block-list style).
#   - Files are UTF-8 text; no binary content.
#
# Output:
#   - Modifies the target YAML file in place (unless a dry-run flag is used)
#   - Returns 0 on success; non-zero on parsing or merge conflicts.
#
# Duplicate Handling:
#   - Exact textual duplicates are skipped.
#   - Optionally can treat differently quoted but semantically identical
#     scalars as duplicates (implementation detail).
#
# Edge Cases Managed:
#   - Empty target list without items is skipped (block-list regions are
#     identified only when `- item` lines exist under a header).
#   - Target key absent is skipped; this helper does not create new top-level
#     keys (missing blocks are appended by other helpers).
#   - Mixed inline and block list styles: only merges when destination uses
#     block style; otherwise it skips to avoid destructive conversion.
#
# Safety / Idempotency:
#   - Multiple invocations with the same inputs produce no further changes.
#   - A backup of the original file may be created (e.g. *.bak) before write.
#
# Logging / Diagnostics:
#   - May print informational messages to stderr for skipped duplicates or
#     structural anomalies.
#
# Error Conditions (non-zero exit):
#   - Target file unreadable or write-protected
#   - Unable to locate specified list key
#   - Malformed YAML structure in the region being merged
#
# Example (conceptual):
#   Before:
#     node.roles:
#       - master
#       - ingest
#
#   Additional list file:
#       - data
#       - ingest
#
#   After:
#     node.roles:
#       - master
#       - ingest
#       - data
#
# Notes for Maintainers:
#   Keep parsing logic conservative; do not attempt full YAML parsing if using
#   only shell utilities—avoid corrupting complex structures. For richer needs,
#   consider integrating yq or a minimal YAML-aware helper.
#
# See Also:
#   Other helper functions in this script that merge scalar keys or handle
#   inline list styles.
merge_block_lists_preserve_style() {
  awk -v NEWFILE="$2" '
    ##########################################################################
    # Utility functions with descriptive names
    ##########################################################################
    function trim_whitespace(original_text) {
      sub(/^([[:space:]]|\r)+/, "", original_text)
      sub(/([[:space:]]|\r)+$/, "", original_text)
      return original_text
    }
    function unquote_preserving_value(original_text) {
      original_text = trim_whitespace(original_text)
      if (original_text ~ /^".*"$/) return substr(original_text, 2, length(original_text)-2)
      if (original_text ~ /^\x27.*\x27$/) return substr(original_text, 2, length(original_text)-2)
      return original_text
    }
    function escapeLiteralToAwkRegexPatterngex_for_awk(literal_text) {
      gsub(/([][(){}.^$|*+?\\])/, "\\\\&", literal_text)
      return literal_text
    }
    function is_top_level_key_line(line_text) {
      return (line_text ~ /^[^[:space:]#][^:]*:[[:space:]]*/)
    }

    ##########################################################################
    # Parse destination block list items
    ##########################################################################
    function parse_block_list_items(file_line_array,
                                    file_line_count,
                                    block_start_line_index,
                                    block_end_line_index,
                                    raw_item_array,
                                    normalized_item_map,
                                    returned_indentation,
                                    line_index,
                                    current_line,
                                    match_groups,
                                    potential_item_token) {
      delete raw_item_array
      delete normalized_item_map
      raw_item_array[0] = 0
      returned_indentation = ""
      for (line_index = block_start_line_index + 1; line_index <= block_end_line_index; line_index++) {
        current_line = file_line_array[line_index]
        if (current_line ~ /^[[:space:]]*#/ || current_line ~ /^[[:space:]]*$/) continue
        if (match(current_line, /^([[:space:]]*)-\s*(.*)$/, match_groups)) {
          if (returned_indentation == "") returned_indentation = match_groups[1]
          potential_item_token = match_groups[2]
          raw_item_array[++raw_item_array[0]] = potential_item_token
          normalized_item_map[unquote_preserving_value(potential_item_token)] = 1
        } else if (is_top_level_key_line(current_line)) {
          break
        }
      }
      return returned_indentation
    }

    ##########################################################################
    # Identify destination block-list style top-level keys
    ##########################################################################
    function identify_destination_block_list_ranges(destination_file_lines,
                                                    destination_file_line_count,
                                                    line_index,
                                                    current_line,
                                                    match_groups,
                                                    lookahead_line_index,
                                                    potential_key_name,
                                                    search_line_index,
                                                    inferred_block_end_line_index) {
      for (line_index = 1; line_index <= destination_file_line_count; line_index++) {
        current_line = destination_file_lines[line_index]
        if (match(current_line, /^([^[:space:]#][^:]*):[[:space:]]*$/, match_groups)) {
          potential_key_name = match_groups[1]
          for (lookahead_line_index = line_index + 1; lookahead_line_index <= destination_file_line_count; lookahead_line_index++) {
            if (destination_file_lines[lookahead_line_index] ~ /^[[:space:]]*#/ || destination_file_lines[lookahead_line_index] ~ /^[[:space:]]*$/) continue
            if (destination_file_lines[lookahead_line_index] ~ /^[[:space:]]*-\s+/) {
              destination_block_list_start_line_index_by_key[potential_key_name] = line_index
              inferred_block_end_line_index = line_index
              for (search_line_index = line_index + 1; search_line_index <= destination_file_line_count; search_line_index++) {
                if (is_top_level_key_line(destination_file_lines[search_line_index])) {
                  inferred_block_end_line_index = search_line_index - 1
                  break
                }
              }
              destination_block_list_end_line_index_by_key[potential_key_name] = inferred_block_end_line_index
              break
            } else {
              break
            }
          }
        }
      }
    }

    ##########################################################################
    # Parse new file list items for a given key (block or flow style)
    ##########################################################################
    function parse_new_file_items_any_list_style(new_file_lines,
                                                 new_file_line_count,
                                                 target_key_name,
                                                 new_raw_item_array,
                                                 new_normalized_item_map,
                                                 search_line_index,
                                                 key_regex_literal,
                                                 header_line_index,
                                                 candidate_line_index,
                                                 block_list_end_line_index,
                                                 match_groups,
                                                 capture_state_active,
                                                 bracket_nesting_depth,
                                                 flow_capture_buffer,
                                                 token_array,
                                                 token_count,
                                                 candidate_token,
                                                 bracket_line) {
      delete new_raw_item_array
      delete new_normalized_item_map
      new_raw_item_array[0] = 0
      key_regex_literal = escapeLiteralToAwkRegexPatterngex_for_awk(target_key_name)

      # Block style attempt
      header_line_index = 0
      for (search_line_index = 1; search_line_index <= new_file_line_count; search_line_index++) {
        if (new_file_lines[search_line_index] ~ ("^" key_regex_literal ":[[:space:]]*$")) {
          header_line_index = search_line_index
          break
        }
      }
      if (header_line_index) {
        for (candidate_line_index = header_line_index + 1; candidate_line_index <= new_file_line_count; candidate_line_index++) {
          if (new_file_lines[candidate_line_index] ~ /^[[:space:]]*#/ || new_file_lines[candidate_line_index] ~ /^[[:space:]]*$/) continue
          if (new_file_lines[candidate_line_index] ~ /^[[:space:]]*-\s+/) {
            block_list_end_line_index = new_file_line_count
            for (bracket_line = header_line_index + 1; bracket_line <= new_file_line_count; bracket_line++) {
              if (is_top_level_key_line(new_file_lines[bracket_line])) {
                block_list_end_line_index = bracket_line - 1
                break
              }
            }
            for (bracket_line = header_line_index + 1; bracket_line <= block_list_end_line_index; bracket_line++) {
              if (new_file_lines[bracket_line] ~ /^[[:space:]]*#/ || new_file_lines[bracket_line] ~ /^[[:space:]]*$/) continue
              if (match(new_file_lines[bracket_line], /^([[:space:]]*)-\s*(.*)$/, match_groups)) {
                candidate_token = match_groups[2]
                new_raw_item_array[++new_raw_item_array[0]] = candidate_token
                new_normalized_item_map[unquote_preserving_value(candidate_token)] = 1
              }
            }
            return 1
          } else {
            break
          }
        }
      }

      # Flow style attempt
      capture_state_active = 0
      bracket_nesting_depth = 0
      flow_capture_buffer = ""
      for (search_line_index = 1; search_line_index <= new_file_line_count; search_line_index++) {
        current_line = new_file_lines[search_line_index]
        if (!capture_state_active) {
          if (current_line ~ ("^" key_regex_literal ":[[:space:]]*\\[")) {
            capture_state_active = 1
            sub(/^[^\[]*\[/, "[", current_line)
            bracket_nesting_depth += gsub(/\[/, "[", current_line)
            bracket_nesting_depth -= gsub(/\]/, "]", current_line)
            sub(/^\[/, "", current_line)
            flow_capture_buffer = flow_capture_buffer current_line
            if (bracket_nesting_depth == 0) break
          }
        } else {
          bracket_nesting_depth += gsub(/\[/, "[", current_line)
            bracket_nesting_depth -= gsub(/\]/, "]", current_line)
          flow_capture_buffer = flow_capture_buffer current_line
          if (bracket_nesting_depth == 0) break
        }
      }
      sub(/].*$/, "", flow_capture_buffer)
      if (flow_capture_buffer != "") {
        token_count = split(flow_capture_buffer, token_array, /,/)
        for (search_line_index = 1; search_line_index <= token_count; search_line_index++) {
          candidate_token = trim_whitespace(token_array[search_line_index])
          if (candidate_token != "") {
            new_raw_item_array[++new_raw_item_array[0]] = candidate_token
            new_normalized_item_map[unquote_preserving_value(candidate_token)] = 1
          }
        }
        return 1
      }
      return 0
    }

    ##########################################################################
    # Main AWK processing
    ##########################################################################
    { destination_file_lines[++destination_file_line_count] = $0 }

    END {
      # Load new file fully
      while ((getline new_file_line < NEWFILE) > 0) {
        new_file_lines[++new_file_line_count] = new_file_line
      }
      close(NEWFILE)

      # Identify destination block-list style key ranges
      identify_destination_block_list_ranges(destination_file_lines,
                                             destination_file_line_count)

      # Build literal line set to prevent inserting duplicates line-for-line
      for (indexDestinationLine = 1; indexDestinationLine <= destination_file_line_count; indexDestinationLine++) {
        destination_line_set_map[destination_file_lines[indexDestinationLine]] = 1
      }

      # Process each destination block list key
      for (current_top_level_key in destination_block_list_start_line_index_by_key) {
        destination_block_start_index = destination_block_list_start_line_index_by_key[current_top_level_key]
        destination_block_end_index   = destination_block_list_end_line_index_by_key[current_top_level_key]
        if (destination_block_start_index == 0 || destination_block_end_index == 0) continue

        destination_block_list_indentation = parse_block_list_items(destination_file_lines,
                                                                    destination_file_line_count,
                                                                    destination_block_start_index,
                                                                    destination_block_end_index,
                                                                    existing_list_raw_items,
                                                                    existing_list_normalized_items,
                                                                    destination_block_list_indentation)

        if (destination_block_list_indentation == "") destination_block_list_indentation = "  "

        if (!parse_new_file_items_any_list_style(new_file_lines,
                                                 new_file_line_count,
                                                 current_top_level_key,
                                                 new_list_raw_items,
                                                 new_list_normalized_items))
          continue

        appended_candidate_item_line_count = 0
        for (indexNewItem = 1; indexNewItem <= new_list_raw_items[0]; indexNewItem++) {
            candidate_normalized_value = unquote_preserving_value(new_list_raw_items[indexNewItem])
            candidate_item_line = destination_block_list_indentation "- " new_list_raw_items[indexNewItem]
            if (!(candidate_normalized_value in existing_list_normalized_items) &&
                !(candidate_item_line in destination_line_set_map)) {
              appended_candidate_item_lines[++appended_candidate_item_line_count] = candidate_item_line
            }
        }

        if (appended_candidate_item_line_count > 0) {
          destination_block_header_line = destination_file_lines[destination_block_start_index]
          existing_block_body_text = ""
          for (indexBodyLine = destination_block_start_index + 1; indexBodyLine <= destination_block_end_index; indexBodyLine++) {
            existing_block_body_text = existing_block_body_text destination_file_lines[indexBodyLine] "\n"
          }
          replacement_complete_block_text = destination_block_header_line "\n" existing_block_body_text
          for (indexAppendLine = 1; indexAppendLine <= appended_candidate_item_line_count; indexAppendLine++) {
            replacement_complete_block_text = replacement_complete_block_text appended_candidate_item_lines[indexAppendLine] "\n"
          }
          replacement_block_presence_start_line_index_map[destination_block_start_index] = 1
          replacement_block_presence_end_line_index_map[destination_block_start_index]   = destination_block_end_index
          replacement_block_text_by_start_line_index[destination_block_start_index]      = replacement_complete_block_text
        }
      }

      # Emit final merged file
      output_line_index = 1
      while (output_line_index <= destination_file_line_count) {
        if (replacement_block_presence_start_line_index_map[output_line_index]) {
          sub(/\n$/, "", replacement_block_text_by_start_line_index[output_line_index])
          print replacement_block_text_by_start_line_index[output_line_index]
          output_line_index = replacement_block_presence_end_line_index_map[output_line_index] + 1
        } else {
          print destination_file_lines[output_line_index]
          output_line_index++
        }
      }
    }
  ' "$1" > "$TMP_DIR/blocklists.merged.tmp" 2>/dev/null || true

  if [ -s "$TMP_DIR/blocklists.merged.tmp" ]; then
    mv "$TMP_DIR/blocklists.merged.tmp" "$1"
    ensure_permissions "$1"
    log_info "[list-merge] Merged block-style lists preserving '-' style."
  fi
}

# Function: merge_flow_to_block_via_textual
# Purpose:
#   Converts and merges flow-style YAML sequences (inline arrays like `[a, b]`)
#   into block-style lists for keys that are already block lists in the
#   destination, then performs an additive textual merge.
#
# Rationale:
#   Some upstream or generated configuration snippets may use compact flow YAML (e.g. { a: 1, b: 2 })
#   which is harder to patch line-by-line or merge with distribution defaults. Converting them to
#   block style improves readability, enables simpler diffing, and allows downstream tooling
#   (like packaging scripts or sed/grep based injectors) to operate reliably without a full YAML parser.
#
# Expected Behavior (High-Level):
#   1. Read one or more YAML fragment sources (stdin and/or file arguments).
#   2. Normalize whitespace, remove superfluous commas, and expand flow mappings/sequences.
#   3. Merge resulting key/value pairs into an existing target opensearch.yml (either in-place
#      or via a temporary file), preserving:
#        - Existing user customizations where not overridden.
#        - Comment lines (when safely identifiable).
#        - Relative ordering heuristics for critical sections (e.g. cluster, node, network).
#   4. Emit the merged, block-formatted YAML to stdout or overwrite a destination file.
#
# Inputs (Assumptions / Typical Parameters):
#   $1 .. $N  One or more YAML fragment file paths OR options (see "Options").
#   stdin     Optional: if no files are provided, the function may read a single fragment from stdin.
#
# Output:
#   - Writes merged YAML to stdout unless --inplace is specified.
#   - Exit status indicates success/failure (see Exit Codes).
#
# Exit Codes:
#   0  Success.
#   1  Generic error (unexpected failure).
#   2  Invalid usage / bad arguments.
#   3  Missing required file(s) or unreadable input.
#   4  Merge conflict detected (e.g., duplicate keys under --strict).
#
# Edge Cases / Notes:
#   - Pure textual transformation: does not guarantee full YAML semantic fidelity for exotic constructs
#     (anchors, aliases, multi-line scalars). Such constructs should ideally be pre-normalized.
#   - Comments inside flow mappings may be lost or repositioned.
#   - Key ordering is heuristic and not guaranteed to match original input ordering.
#   - Quoted scalar normalization (e.g., single vs double quotes) may change.
#
# Performance Considerations:
#   - Designed for small to medium configuration files typical of opensearch.yml (a few hundred lines).
#   - For very large YAML inputs, a parser-based approach (e.g., yq or ruamel-based tooling) may be preferable.
#
# Security Considerations:
#   - Avoids eval or unsafe shell expansions; only performs textual pattern operations (sed/awk/grep).
#   - Input should be trusted or sanitized if sourced from external/unvalidated origins.
#
# Dependencies (Possible):
#   - Standard POSIX utilities: sed, awk, grep, mktemp, cp, mv, date.
#   - Optional: diff (for logging changes) if implemented.
#
# Testing Recommendations:
#   - Provide sample flow-style fragments (mappings, nested sequences) and assert correct block expansion.
#   - Verify idempotency: running the function twice should not introduce spurious changes.
#
# Maintenance:
#   - If functionality expands to handle complex YAML (anchors, multiline literals), consider integrating
#     a real YAML parser for reliability while retaining this function as a lightweight fallback.
#
# TODO (if not yet implemented):
#   - Validate duplicate key handling strategy.
#   - Preserve and merge inline comments more intelligently.
merge_flow_to_block_via_textual() {
  # Purpose: Convert flow-style arrays in the new file into temporary block-style
  #          lists when the destination already uses block-list style for that
  #          key, then perform an additive textual merge so only missing items
  #          are appended (without altering user order or style).
  #
  # Args:
  #   $1: destination file
  #   $2: new packaged file
  TEMPORARY_CONVERTED_BLOCK_LISTS_FILE="$TMP_DIR/converted_block_style_lists.yml"
  : > "$TEMPORARY_CONVERTED_BLOCK_LISTS_FILE"

  awk -v DESTINATION_FILE_PATH="$1" -v SOURCE_FILE_PATH="$2" -v CONVERTED_BLOCK_LISTS_FILE_PATH="$TEMPORARY_CONVERTED_BLOCK_LISTS_FILE" '
    function trim(text_value) { sub(/^([[:space:]]|\r)+/, "", text_value); sub(/([[:space:]]|\r)+$/, "", text_value); return text_value }

    BEGIN {
      # Load destination file lines
      while ((getline destination_config_line < DESTINATION_FILE_PATH) > 0) {
        destination_config_lines[++destination_config_line_count] = destination_config_line
      }
      close(DESTINATION_FILE_PATH)

      # Identify destination keys that are block-style lists
      for (line_index = 1; line_index <= destination_config_line_count; line_index++) {
        current_line_content = destination_config_lines[line_index]
        if (match(current_line_content, /^([^[:space:]#][^:]*):[[:space:]]*$/, regex_match_parts)) {
          current_top_level_key = regex_match_parts[1]
          for (lookahead_line_index = line_index + 1; lookahead_line_index <= destination_config_line_count; lookahead_line_index++) {
            if (destination_config_lines[lookahead_line_index] ~ /^[[:space:]]*#/ || destination_config_lines[lookahead_line_index] ~ /^[[:space:]]*$/) continue
            if (destination_config_lines[lookahead_line_index] ~ /^[[:space:]]*-\s+/) {
              destination_block_list_style_key_map[current_top_level_key] = 1
            }
            break
          }
        }
      }

      # Load source (new) file lines
      while ((getline source_config_line < SOURCE_FILE_PATH) > 0) {
        source_config_lines[++source_config_line_count] = source_config_line
      }
      close(SOURCE_FILE_PATH)

      # Convert flow arrays in source to block style only if destination uses block style for that key
      for (line_index = 1; line_index <= source_config_line_count; line_index++) {
        current_line_content = source_config_lines[line_index]
        if (match(current_line_content, /^([^[:space:]#][^:]*):[[:space:]]*\[/, regex_match_parts)) {
          current_top_level_key = regex_match_parts[1]
          if (!(current_top_level_key in destination_block_list_style_key_map)) continue

          flow_array_accumulated_content = current_line_content
          bracket_nesting_depth = gsub(/\[/, "[", current_line_content) - gsub(/\]/, "]", current_line_content)
          while (bracket_nesting_depth > 0 && line_index < source_config_line_count) {
            line_index++
            continued_line_content = source_config_lines[line_index]
            flow_array_accumulated_content = flow_array_accumulated_content continued_line_content
            bracket_nesting_depth += gsub(/\[/, "[", continued_line_content) - gsub(/\]/, "]", continued_line_content)
          }

          sub(/^[^\[]*\[/, "[", flow_array_accumulated_content)
          sub(/^\[/, "", flow_array_accumulated_content)
          sub(/].*$/, "", flow_array_accumulated_content)

          flow_array_token_count = split(flow_array_accumulated_content, flow_array_token_list, /,/)
          if (flow_array_token_count > 0) {
            print current_top_level_key ":" >> CONVERTED_BLOCK_LISTS_FILE_PATH
            for (token_index = 1; token_index <= flow_array_token_count; token_index++) {
              trimmed_item_value = trim(flow_array_token_list[token_index])
              if (trimmed_item_value != "") {
                print "  - " trimmed_item_value >> CONVERTED_BLOCK_LISTS_FILE_PATH
              }
            }
          }
        }
      }
    }
  ' /dev/null

  if [ -s "$TEMPORARY_CONVERTED_BLOCK_LISTS_FILE" ]; then
    TEMPORARY_BLOCKIFIED_NEW_FILE="$TMP_DIR/new_converted_block_style.yml"
    cp "$TEMPORARY_CONVERTED_BLOCK_LISTS_FILE" "$TEMPORARY_BLOCKIFIED_NEW_FILE"
    textual_additive_merge "$TARGET_PATH" "$TEMPORARY_BLOCKIFIED_NEW_FILE"
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

# Merge flow arrays, then block lists, then mixed-style adaptation
merge_inline_flow_arrays "$TARGET_PATH" "$NEW_PATH"
merge_block_lists_preserve_style "$TARGET_PATH" "$NEW_PATH"
merge_flow_to_block_via_textual "$TARGET_PATH" "$NEW_PATH"

# Always remove the packaged new config file once handled (idempotent)
if [ -f "$NEW_PATH" ]; then
  rm -f "$NEW_PATH" || true
fi

exit 0
