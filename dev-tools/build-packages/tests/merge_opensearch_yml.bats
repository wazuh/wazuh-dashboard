#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MERGE_SCRIPT="$REPO_DIR/config/merge_opensearch_yml.sh"
  TMPDIR_TEST=$(mktemp -d)
  CONFIG_DIR="$TMPDIR_TEST/etc/wazuh-dashboard"
  mkdir -p "$CONFIG_DIR"
  OPENSEARCH_DASHBOARD_YML="$CONFIG_DIR/opensearch_dashboards.yml"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "no new config file: script exits quietly and leaves file untouched" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 0.0.0.0
existing.key: value
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ -f "$OPENSEARCH_DASHBOARD_YML" ]
  # unchanged content
  run grep -Fx "existing.key: value" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "rpmnew: appends only missing keys and removes .rpmnew" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 0.0.0.0
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
# comment line should be ignored
server.host: 0.0.0.0
new.setting: true
another.setting: 123
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
  # Active should include the new keys appended once
  run grep -Fx "new.setting: true" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "another.setting: 123" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  # Idempotent: running again doesn't duplicate
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ $(grep -Fc "new.setting: true" "$OPENSEARCH_DASHBOARD_YML") -eq 1 ]
  # Permissions set to 0640
  PERM=$(stat -c %a "$OPENSEARCH_DASHBOARD_YML" 2>/dev/null || stat -f %Lp "$OPENSEARCH_DASHBOARD_YML")
  [ "$PERM" = "640" ]
}

@test "dpkg-dist: preserves existing keys and adds only missing ones" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 0.0.0.0
existing.key: 1
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
existing.key: 2
new.key: abc
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  # existing.key should remain 1
  run grep -Fx "existing.key: 1" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -F "existing.key: 2" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -ne 0 ]
  # new.key should be added
  run grep -Fx "new.key: abc" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test ".dpkg-new: supported alias file name" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 127.0.0.1
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-new" <<'YML'
added.key: yes
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-new" ]
  run grep -Fx "added.key: yes" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "custom user config: keep existing values, add only missing defaults" {
  # User's current config with custom values
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
# User customizations
server.host: 0.0.0.0
server.port: 5602
opensearch.ssl.verificationMode: none
telemetry.enabled: true
YML

  # New defaults shipped by package (some overlap with different values)
  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
server.host: 127.0.0.1
server.port: 5601
opensearch.ssl.verificationMode: full
telemetry.enabled: false
i18n.locale: en
newsfeed.enabled: false
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]

  # Existing keys remain with user values, no duplicates
  run grep -Fx "server.host: 0.0.0.0" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -F "server.host: 127.0.0.1" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -ne 0 ]

  run grep -Fx "server.port: 5602" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -F "server.port: 5601" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -ne 0 ]

  run grep -Fx "opensearch.ssl.verificationMode: none" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -F "opensearch.ssl.verificationMode: full" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -ne 0 ]

  # Missing keys are appended
  run grep -Fx "i18n.locale: en" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "newsfeed.enabled: false" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "whitespace/comments: existing key not duplicated despite formatting differences" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
# Spaces and comments
telemetry.enabled:   true
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
# New default sets telemetry to false, but key already exists
telemetry.enabled: false
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  # Key appears only once
  [ $(grep -c '^telemetry\.enabled:' "$OPENSEARCH_DASHBOARD_YML") -eq 1 ]
}

@test "partial overlap: multiple defaults provided, only absent keys added" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 0.0.0.0
logging.verbose: false
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
server.host: 127.0.0.1
logging.verbose: true
logging.dest: stdout
i18n.locale: en
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]

  # Existing kept
  run grep -Fx "server.host: 0.0.0.0" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "logging.verbose: false" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  # Only missing added
  run grep -Fx "logging.dest: stdout" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "i18n.locale: en" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "post-install: add new default setting if missing" {
  # Active config is missing some of the new defaults
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
existing.key: old
another.present: yes
YML

  # New defaults shipped in packaged file
  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
existing.key: changed
new.default.one: 42
new.default.two: value
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]

  # Should NOT add existing.key again
  [ $(grep -c '^existing\.key:' "$OPENSEARCH_DASHBOARD_YML") -eq 1 ]
  run grep -Fx "existing.key: old" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]

  # Should add exactly the missing defaults
  run grep -Fx "new.default.one: 42" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "new.default.two: value" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "post-install: nothing to add when user already has all settings" {
  # Active already contains all keys
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
keep.this: 1
new.default.one: 42
new.default.two: value
YML

  cp "$OPENSEARCH_DASHBOARD_YML" "$OPENSEARCH_DASHBOARD_YML.copy"

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
keep.this: 9
new.default.one: 42
new.default.two: value
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  # No changes applied (exact match with copy)
  run diff -u "$OPENSEARCH_DASHBOARD_YML.copy" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}
