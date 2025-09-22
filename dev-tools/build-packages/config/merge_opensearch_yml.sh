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

# From the new file, find keys that are not present and collect their single-line definitions
awk -v existing="$TMP_DIR/existing_keys.txt" -v added="$ADDED_KEYS_FILE" -v out="$APPEND_FILE" '
  BEGIN {
    while ((getline k < existing) > 0) { have[k]=1 }
    close(existing)
  }
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  {
    if (match($0, /^[[:space:]]*([^:#]+)[[:space:]]*:/, m)) {
      key=m[1]
      gsub(/[[:space:]]+$/, "", key)
      if (!have[key] && !printed[key]) {
        print $0 >> out
        print key >> added
        printed[key]=1
      }
    }
  }
' "$NEW_PATH"

if [ -s "$APPEND_FILE" ]; then
  echo "# --- Added new default settings on $(date -u +"%Y-%m-%dT%H:%M:%SZ") ---" >> "$TARGET_PATH"
  cat "$APPEND_FILE" >> "$TARGET_PATH"

  # Try to preserve expected ownership and permissions
  if id wazuh-dashboard >/dev/null 2>&1; then
    chown wazuh-dashboard:wazuh-dashboard "$TARGET_PATH" || true
  fi
  chmod 0640 "$TARGET_PATH" || true

  echo "Merged new default keys into ${TARGET_PATH}:"
  sed 's/^/  - /' "$ADDED_KEYS_FILE" 1>&2 || true
fi

# Remove the pending new config file to avoid future prompts
rm -f "$NEW_PATH"

rm -rf "$TMP_DIR"
exit 0

