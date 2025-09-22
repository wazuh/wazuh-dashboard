#!/bin/sh
# Merge new default settings from a packaged opensearch_dashboards.yml
# into the active /etc/wazuh-dashboard/opensearch_dashboards.yml, only
# adding keys that do not already exist.

set -e

CONFIG_DIR="/etc/wazuh-dashboard"
TARGET_FILE="opensearch_dashboards.yml"

while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir)
      CONFIG_DIR="$2"; shift 2;;
    --help|-h)
      echo "Usage: $0 [--config-dir /etc/wazuh-dashboard]"; exit 0;;
    *)
      # ignore unknown
      shift;;
  esac
done

TARGET_PATH="${CONFIG_DIR}/${TARGET_FILE}"

# Identify the new config file name produced by the package manager
CANDIDATES="${TARGET_PATH}.rpmnew ${TARGET_PATH}.dpkg-dist ${TARGET_PATH}.dpkg-new ${TARGET_PATH}.ucf-dist"
NEW_PATH=""
for f in $CANDIDATES; do
  if [ -f "$f" ]; then
    NEW_PATH="$f"
    break
  fi
done

# Nothing to do if there is no pending new config file
if [ -z "$NEW_PATH" ] || [ ! -f "$TARGET_PATH" ]; then
  exit 0
fi

TMP_DIR=$(mktemp -d)
APPEND_FILE="$TMP_DIR/append.yml"
ADDED_KEYS_FILE="$TMP_DIR/added_keys.txt"

# Build a set of existing keys from the current config (top-level, non-comment lines)
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

# Detect Mike Farah yq v4+ (deep merge capable)
YQ_OK=false
if command -v yq >/dev/null 2>&1; then
  if yq --version 2>&1 | grep -Ei 'mikefarah|https://github.com/mikefarah/yq' >/dev/null 2>&1; then
    YQ_OK=true
  fi
fi

# If yq (Mike Farah) is available, compute a deep-add patch of only missing keys
if [ "$YQ_OK" = "true" ]; then
  yq ea -n '
    # fileIndex: 0 -> existing, 1 -> new
    (select(fileIndex==0)) as $old |
    (select(fileIndex==1)) as $new |
    reduce ($new | paths(scalars)) as $p ({};
      (try ($old | getpath($p)) catch null) as $ov |
      if $ov == null then setpath($p; $new | getpath($p)) else . end
    )
  ' "$TARGET_PATH" "$NEW_PATH" > "$APPEND_FILE" || true
  # Record added top-level keys (best-effort)
  yq e 'keys | .[]' "$APPEND_FILE" 2>/dev/null | sed 's/^/+/g' > "$ADDED_KEYS_FILE" || true
else
  ############################################
  # Fallback: collect full top-level blocks from new file
  ############################################
  awk -v existing="$TMP_DIR/existing_keys.txt" -v added="$ADDED_KEYS_FILE" -v out="$APPEND_FILE" '
    BEGIN {
      while ((getline k < existing) > 0) { have[k]=1 }
      close(existing)
    }
    {
      lines[NR]=$0
    }
    END {
      n = NR
      # discover top-level keys and their starting line numbers
      for (i=1; i<=n; i++) {
        line = lines[i]
      if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
      if (line ~ /^[^[:space:]#][^:]*:[[:space:]]*/) {
        # extract key name before colon
        key=line
        sub(/:.*/, "", key)
        gsub(/[[:space:]]+$/, "", key)
        if (!(key in start)) {
            order[++orderN]=key
            start[key]=i
          }
        }
      }
      # compute end lines
      for (idx=1; idx<=orderN; idx++) {
        k=order[idx]
        s=start[k]
        e=n
        if (idx < orderN) {
          nk=order[idx+1]
          e = start[nk]-1
        }
        if (!(k in have) && !(k in printed)) {
          # append full block for missing top-level key
          for (j=s; j<=e; j++) print lines[j] >> out
          print k >> added
          printed[k]=1
        }
      }
    }
  ' "$NEW_PATH"
fi

NONEMPTY=true
if [ "$YQ_OK" = "true" ]; then
  if yq e 'length == 0' "$APPEND_FILE" >/dev/null 2>&1; then
    NONEMPTY=false
  fi
else
  # Treat '{}' or empty as empty when yq is not present
  if [ -f "$APPEND_FILE" ] && grep -Eq '^[[:space:]]*\{\}[[:space:]]*$' "$APPEND_FILE"; then
    NONEMPTY=false
  fi
fi

if [ -s "$APPEND_FILE" ] && [ "$NONEMPTY" = "true" ]; then
  echo "# --- Added new default settings on $(date -u +"%Y-%m-%dT%H:%M:%SZ") ---" >> "$TARGET_PATH"
  cat "$APPEND_FILE" >> "$TARGET_PATH"

  # Try to preserve expected ownership and permissions
  if id wazuh-dashboard >/dev/null 2>&1; then
    chown wazuh-dashboard:wazuh-dashboard "$TARGET_PATH" || true
  fi
  chmod 0640 "$TARGET_PATH" || true

  echo "Merged new default keys into ${TARGET_PATH}:" 1>&2
  if [ -s "$ADDED_KEYS_FILE" ]; then
    sed 's/^/  - /' "$ADDED_KEYS_FILE" 1>&2 || true
  fi
fi

# Remove the pending new config file to avoid future prompts
rm -f "$NEW_PATH"

rm -rf "$TMP_DIR"
exit 0
