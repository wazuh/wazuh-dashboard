#!/bin/sh
# Merge new default settings from a packaged opensearch_dashboards.yml
# into the active /etc/wazuh-dashboard/opensearch_dashboards.yml, only
# adding keys that do not already exist. Supports deep additive merge
# when Mike Farah yq v4+ is available; otherwise falls back to
# top-level block append.

set -e

CONFIG_DIR="/etc/wazuh-dashboard"
TARGET_FILE="opensearch_dashboards.yml"

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir)
      CONFIG_DIR="$2"; shift 2;;
    --help|-h)
      echo "Usage: $0 [--config-dir /etc/wazuh-dashboard]"; exit 0;;
    *) shift;;
  esac
done

TARGET_PATH="${CONFIG_DIR}/${TARGET_FILE}"

# Identify the new config file name produced by the package manager
CANDIDATES="${TARGET_PATH}.rpmnew ${TARGET_PATH}.dpkg-dist ${TARGET_PATH}.dpkg-new ${TARGET_PATH}.ucf-dist"
NEW_PATH=""
for f in $CANDIDATES; do
  if [ -f "$f" ]; then NEW_PATH="$f"; break; fi
done

# Nothing to do if there is no pending new config file or target is missing
if [ -z "$NEW_PATH" ] || [ ! -f "$TARGET_PATH" ]; then
  exit 0
fi

TMP_DIR=$(mktemp -d)
APPEND_FILE="$TMP_DIR/append.yml"
PATCH_FILE="$TMP_DIR/patch.yml"
MERGED_FILE="$TMP_DIR/merged.yml"
ADDED_KEYS_FILE="$TMP_DIR/added_keys.txt"

# Detect Mike Farah yq v4+
YQ_PRESENT=false
YQ_OK=false
if command -v yq >/dev/null 2>&1; then
  YQ_PRESENT=true
  if yq --version 2>&1 | grep -Ei 'mikefarah|https://github.com/mikefarah/yq' >/dev/null 2>&1; then
    YQ_OK=true
  fi
fi

if [ "$YQ_OK" = "true" ]; then
  # Build a patch that contains only missing scalar leaves from NEW_PATH compared to TARGET_PATH
  yq ea -n '
    (select(fileIndex==0)) as $old |
    (select(fileIndex==1)) as $new |
    reduce ($new | paths(scalars)) as $p ({};
      (try ($old | getpath($p)) catch null) as $ov |
      if $ov == null then setpath($p; $new | getpath($p)) else . end
    )
  ' "$TARGET_PATH" "$NEW_PATH" > "$PATCH_FILE" || true

  # If there is something to add, merge patch into target without overwriting
  if [ -s "$PATCH_FILE" ] && [ "$(yq e 'length == 0' "$PATCH_FILE" 2>/dev/null || echo false)" != "true" ]; then
    yq ea -n '
      (select(fileIndex==0)) as $old |
      (select(fileIndex==1)) as $patch |
      $old *d $patch
    ' "$TARGET_PATH" "$PATCH_FILE" > "$MERGED_FILE" && mv "$MERGED_FILE" "$TARGET_PATH"

    # Try to preserve expected ownership and permissions
    if id wazuh-dashboard >/dev/null 2>&1; then
      chown wazuh-dashboard:wazuh-dashboard "$TARGET_PATH" || true
    fi
    chmod 0640 "$TARGET_PATH" || true

    # Log added top-level keys (best effort)
    yq e 'keys | .[]' "$PATCH_FILE" 2>/dev/null | sed 's/^/  - /' > "$ADDED_KEYS_FILE" || true
    if [ -s "$ADDED_KEYS_FILE" ]; then
      echo "Merged new default keys into ${TARGET_PATH}:" 1>&2
      cat "$ADDED_KEYS_FILE" 1>&2 || true
    fi
  fi
elif [ "$YQ_PRESENT" = "true" ]; then
  # yq is present (jq-wrapper style). Use jq-based deep additive merge.
  OLD_JSON="$TMP_DIR/old.json"
  NEW_JSON="$TMP_DIR/new.json"
  # First, append any missing top-level blocks textually to preserve formatting
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      if (match($0, /^[[:space:]]*([^:#]+)[[:space:]]*:/, m)) {
        key=m[1]; gsub(/[[:space:]]+$/, "", key); print key
      }
    }
  ' "$TARGET_PATH" | sed 's/[[:space:]]*$//' | sort -u > "$TMP_DIR/existing_keys.txt"

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
  ' "$NEW_PATH"

  DID_APPEND=0
  if [ -s "$APPEND_FILE" ]; then
    echo "# --- Added new default settings on $(date -u +"%Y-%m-%dT%H:%M:%SZ") ---" >> "$TARGET_PATH"
    cat "$APPEND_FILE" >> "$TARGET_PATH"
    DID_APPEND=1
  fi

  # Now perform deep merge only under existing top-level keys
  if [ "$DID_APPEND" -eq 0 ]; then
  yq '.' "$TARGET_PATH" > "$OLD_JSON"
  yq '.' "$NEW_PATH" > "$NEW_JSON"
  # Determine if there are missing nested keys under existing top-level keys
  MISSING_NESTED=$(jq -s '[ (.[1]|paths(scalars)) as $p | select(((.[0]|keys)|index($p[0])) and ((.[0]|getpath($p)? // null) == null)) ] | length' "$OLD_JSON" "$NEW_JSON" 2>/dev/null || echo 0)

  if [ "$MISSING_NESTED" -gt 0 ] 2>/dev/null; then
    # Textual merge for known nested key: uiSettings
    if grep -q '^uiSettings:' "$TARGET_PATH" && grep -q '^uiSettings:' "$NEW_PATH"; then
      # Extract lines after 'uiSettings:' from NEW
      awk '/^uiSettings:[[:space:]]*$/{flag=1; next} /^[^[:space:]#][^:]*:[[:space:]]*/{if(flag){exit}} flag{print}' "$NEW_PATH" > "$TMP_DIR/ui_block.new"
      if [ -s "$TMP_DIR/ui_block.new" ]; then
        # Determine end of uiSettings block in TARGET
        awk -v tmpfile="$TMP_DIR/ui_block.new" '
          BEGIN{printed=0}
          /^uiSettings:[[:space:]]*$/ {print; ui=1; next}
          /^[^[:space:]#][^:]*:[[:space:]]*/ { if (ui && !printed) { while ((getline line < tmpfile) > 0) { if (line != "" && system("grep -Fqx \"" line "\" \"" FILENAME "\"") != 0) print line } close(tmpfile); printed=1; ui=0 } }
          {print}
          END{ if (ui && !printed) { while ((getline line < tmpfile) > 0) { if (line != "" && system("grep -Fqx \"" line "\" \"" FILENAME "\"") != 0) print line } close(tmpfile) } }
        ' "$TARGET_PATH" > "$TMP_DIR/target.with.ui.yml" 2>/dev/null || true
        if [ -s "$TMP_DIR/target.with.ui.yml" ]; then
          mv "$TMP_DIR/target.with.ui.yml" "$TARGET_PATH"
        fi
      fi
    fi
  fi
  fi
    if id wazuh-dashboard >/dev/null 2>&1; then
      chown wazuh-dashboard:wazuh-dashboard "$TARGET_PATH" || true
    fi
    chmod 0640 "$TARGET_PATH" || true
else
  # Fallback: build a set of existing top-level keys
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      if (match($0, /^[[:space:]]*([^:#]+)[[:space:]]*:/, m)) {
        key=m[1]
        gsub(/[[:space:]]+$/, "", key)
        print key
      }
    }
  ' "$TARGET_PATH" | sed 's/[[:space:]]*$//' | sort -u > "$TMP_DIR/existing_keys.txt"

  # Collect full top-level blocks from the new file for keys that are missing
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
  ' "$NEW_PATH"

  if [ -s "$APPEND_FILE" ]; then
    echo "# --- Added new default settings on $(date -u +"%Y-%m-%dT%H:%M:%SZ") ---" >> "$TARGET_PATH"
    cat "$APPEND_FILE" >> "$TARGET_PATH"

    if id wazuh-dashboard >/dev/null 2>&1; then
      chown wazuh-dashboard:wazuh-dashboard "$TARGET_PATH" || true
    fi
    chmod 0640 "$TARGET_PATH" || true

    if [ -s "$ADDED_KEYS_FILE" ]; then
      echo "Merged new default keys into ${TARGET_PATH}:" 1>&2
      sed 's/^/  - /' "$ADDED_KEYS_FILE" 1>&2 || true
    fi
  fi
fi

# Remove the pending new config file to avoid future prompts
rm -f "$NEW_PATH"
rm -rf "$TMP_DIR"
exit 0
