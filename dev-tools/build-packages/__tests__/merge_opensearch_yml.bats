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

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  echo "$output"
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

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
  # Active should include the new keys appended once
  run grep -Fx "new.setting: true" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "another.setting: 123" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  # Idempotent: running again doesn't duplicate
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
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

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
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

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-new" ]
  run grep -Eq '^added\.key: yes$' "$OPENSEARCH_DASHBOARD_YML"
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

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
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

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  # Key appears only once
  [ $(grep -c '^telemetry\.enabled:' "$OPENSEARCH_DASHBOARD_YML") -eq 1 ]
}

@test "commented-out existing key should still be added as active setting" {
  # User has the key commented; should not count as existing
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
# new.default.one: 42
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
new.default.one: 42
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  run grep -Fx "new.default.one: 42" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
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

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
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

@test "nested block default (.rpmnew): copy entire block when top-level key missing" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 0.0.0.0
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
  # Full block appended preserving indentation and quoted key
  run grep -Fx "uiSettings:" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "  overrides:" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Eq "^[[:space:]]{4}[\"']?home:useNewHomePage[\"']?:[[:space:]]*true[[:space:]]*$" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "nested block present in active: do not duplicate top-level key" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  # Only one top-level uiSettings key remains
  [ $(grep -c '^uiSettings:' "$OPENSEARCH_DASHBOARD_YML") -eq 1 ]
}

@test "deep merge: add missing nested block under existing top-level" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
uiSettings:
  # user has no overrides yet
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  run grep -Fx "  overrides:" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "    \"home:useNewHomePage\": true" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "deep merge: add missing leaf under existing nested object" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
uiSettings:
  overrides:
    "some:otherFlag": false
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
  run grep -Fx "    \"some:otherFlag\": false" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
  run grep -Fx "    \"home:useNewHomePage\": true" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "deep merge: no change if nested leaf already present" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  cp "$OPENSEARCH_DASHBOARD_YML" "$OPENSEARCH_DASHBOARD_YML.copy"

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-new" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-new" ]
  run diff -u "$OPENSEARCH_DASHBOARD_YML.copy" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "edge: empty .rpmnew is removed and no changes applied" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 0.0.0.0
YML

  : > "$OPENSEARCH_DASHBOARD_YML.rpmnew"

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
  # File unchanged
  run grep -Fx "server.host: 0.0.0.0" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]
}

@test "edge: target missing but .rpmnew exists -> no action and .rpmnew remains" {
  # Do not create destination file on purpose
  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
added.key: value
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  # Script exits early and does not remove the packaged file
  [ -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
}

@test "block list merge: append missing items, preserve '-' style" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
xs:
  - a
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
xs:
  - a
  - b
  - "c"
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" ]
  # Existing item remains once
  COUNT_A=$(grep -Ec '^\s*-\s*a$' "$OPENSEARCH_DASHBOARD_YML")
  [ "$COUNT_A" -eq 1 ]
  # Missing items appended at the end, preserving block style
  run grep -Eq '^\s*-\s*b$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
  run grep -Eq '^\s*-\s*"c"$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
}

@test "mixed styles: dest flow [], new block '-' -> keep flow and append missing" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
xs: [a]
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
xs:
  - a
  - b
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; [ "$status" -eq 0 ]
  run grep -Fx 'xs: [a, b]' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
}

@test "mixed styles: dest block '-', new flow [] -> keep block and append missing" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
xs:
  - a
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-new" <<'YML'
xs: [a, b]
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; [ "$status" -eq 0 ]
  # Keep block style in destination and add b
  run grep -Eq '^\s*-\s*a$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
  run grep -Eq '^\s*-\s*b$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
  # No single-line flow should remain
  run grep -Fx 'xs: [a, b]' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -ne 0 ]
}

@test "edge: malformed .rpmnew does not crash and removes packaged file" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
existing.key: 1
YML

  # Malformed YAML
  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
bad: [
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  # Packaged file removed regardless
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
  # Destination unchanged
  run grep -Fx "existing.key: 1" "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
}

@test "edge: commented new block is ignored" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
server.host: 0.0.0.0
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
# uiSettings:
#   overrides:
#     "home:useNewHomePage": true
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]
  [ ! -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]
  # No uiSettings added
  run grep -E '^uiSettings:' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -ne 0 ]
}

@test "edge: idempotent nested injection when rerun" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
uiSettings:
  overrides:
    "some:otherFlag": false
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
uiSettings:
  overrides:
    "home:useNewHomePage": true
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; [ "$status" -eq 0 ]
  # Run again, should not duplicate
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; [ "$status" -eq 0 ]
  COUNT=$(grep -Ec "^[[:space:]]{4}[\"']?home:useNewHomePage[\"']?:[[:space:]]*true[[:space:]]*$" "$OPENSEARCH_DASHBOARD_YML")
  [ "$COUNT" -eq 1 ]
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

@test "inline array merge: append missing values for plugins.security.system_indices.indices" {
  # Active config contains the 4.13.0 indices (quoted) only
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
plugins.security.system_indices.indices: [".plugins-ml-model", ".plugins-ml-task", ".opendistro-alerting-config", ".opendistro-alerting-alert*", ".opendistro-anomaly-results*", ".opendistro-anomaly-detector*", ".opendistro-anomaly-checkpoints", ".opendistro-anomaly-detection-state", ".opendistro-reports-*", ".opensearch-notifications-*", ".opensearch-notebooks", ".opensearch-observability", ".opendistro-asynchronous-search-response*", ".replication-metadata-store"]
YML

  # New defaults (4.14.0) include permission flag and a longer indices array (flow style, multi-line)
  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
plugins.security.system_indices.permission.enabled: true
plugins.security.system_indices.indices: [.plugins-ml-agent, .plugins-ml-config, .plugins-ml-connector,
  .plugins-ml-controller, .plugins-ml-model-group, .plugins-ml-model, .plugins-ml-task,
  .plugins-ml-conversation-meta, .plugins-ml-conversation-interactions, .plugins-ml-memory-meta,
  .plugins-ml-memory-message, .plugins-ml-stop-words, .opendistro-alerting-config,
  .opendistro-alerting-alert*, .opendistro-anomaly-results*, .opendistro-anomaly-detector*,
  .opendistro-anomaly-checkpoints, .opendistro-anomaly-detection-state, .opendistro-reports-*,
  .opensearch-notifications-*, .opensearch-notebooks, .opensearch-observability, .ql-datasources,
  .opendistro-asynchronous-search-response*, .replication-metadata-store, .opensearch-knn-models,
  .geospatial-ip2geo-data*, .plugins-flow-framework-config, .plugins-flow-framework-templates,
  .plugins-flow-framework-state, .plugins-search-relevance-experiment, .plugins-search-relevance-judgment-cache]
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]

  # Permission flag added as new key
  run grep -Fx "plugins.security.system_indices.permission.enabled: true" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]

  # Indices array merged by appending only missing values (keep existing order)
  expected='plugins.security.system_indices.indices: [".plugins-ml-model", ".plugins-ml-task", ".opendistro-alerting-config", ".opendistro-alerting-alert*", ".opendistro-anomaly-results*", ".opendistro-anomaly-detector*", ".opendistro-anomaly-checkpoints", ".opendistro-anomaly-detection-state", ".opendistro-reports-*", ".opensearch-notifications-*", ".opensearch-notebooks", ".opensearch-observability", ".opendistro-asynchronous-search-response*", ".replication-metadata-store", .plugins-ml-agent, .plugins-ml-config, .plugins-ml-connector, .plugins-ml-controller, .plugins-ml-model-group, .plugins-ml-conversation-meta, .plugins-ml-conversation-interactions, .plugins-ml-memory-meta, .plugins-ml-memory-message, .plugins-ml-stop-words, .ql-datasources, .opensearch-knn-models, .geospatial-ip2geo-data*, .plugins-flow-framework-config, .plugins-flow-framework-templates, .plugins-flow-framework-state, .plugins-search-relevance-experiment, .plugins-search-relevance-judgment-cache]'
  run grep -Fx "$expected" "$OPENSEARCH_DASHBOARD_YML"; echo "$output" >&3
  [ "$status" -eq 0 ]
}

@test "inline array merge: idempotent on rerun (no duplicates)" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
plugins.security.system_indices.indices: [".plugins-ml-model", ".plugins-ml-task", ".opendistro-alerting-config", ".opendistro-alerting-alert*", ".opendistro-anomaly-results*", ".opendistro-anomaly-detector*", ".opendistro-anomaly-checkpoints", ".opendistro-anomaly-detection-state", ".opendistro-reports-*", ".opensearch-notifications-*", ".opensearch-notebooks", ".opensearch-observability", ".opendistro-asynchronous-search-response*", ".replication-metadata-store"]
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
plugins.security.system_indices.indices: [.plugins-ml-agent, .plugins-ml-model]
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; [ "$status" -eq 0 ]
  # Rerun should not duplicate appended entries
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; [ "$status" -eq 0 ]
  COUNT=$(grep -o "\.plugins-ml-agent" "$OPENSEARCH_DASHBOARD_YML" | wc -l | tr -d ' ')
  [ "$COUNT" -eq 1 ]
}

@test "system_indices: block list merge preserves '-' and appends missing (new flow style)" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
plugins.security.system_indices.indices:
  - ".plugins-ml-model"
  - ".plugins-ml-task"
  - ".opendistro-alerting-config"
  - ".opendistro-alerting-alert*"
  - ".opendistro-anomaly-results*"
  - ".opendistro-anomaly-detector*"
  - ".opendistro-anomaly-checkpoints"
  - ".opendistro-anomaly-detection-state"
  - ".opendistro-reports-*"
  - ".opensearch-notifications-*"
  - ".opensearch-notebooks"
  - ".opensearch-observability"
  - ".opendistro-asynchronous-search-response*"
  - ".replication-metadata-store"
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.rpmnew" <<'YML'
plugins.security.system_indices.permission.enabled: true
plugins.security.system_indices.indices: [.plugins-ml-agent, .plugins-ml-config, .plugins-ml-connector,
  .plugins-ml-controller, .plugins-ml-model-group, .plugins-ml-model, .plugins-ml-task,
  .plugins-ml-conversation-meta, .plugins-ml-conversation-interactions, .plugins-ml-memory-meta,
  .plugins-ml-memory-message, .plugins-ml-stop-words, .opendistro-alerting-config,
  .opendistro-alerting-alert*, .opendistro-anomaly-results*, .opendistro-anomaly-detector*,
  .opendistro-anomaly-checkpoints, .opendistro-anomaly-detection-state, .opendistro-reports-*,
  .opensearch-notifications-*, .opensearch-notebooks, .opensearch-observability, .ql-datasources,
  .opendistro-asynchronous-search-response*, .replication-metadata-store, .opensearch-knn-models,
  .geospatial-ip2geo-data*, .plugins-flow-framework-config, .plugins-flow-framework-templates,
  .plugins-flow-framework-state, .plugins-search-relevance-experiment, .plugins-search-relevance-judgment-cache]
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; echo "$output" >&3
  [ "$status" -eq 0 ]

  # Permission flag added
  run grep -Fx "plugins.security.system_indices.permission.enabled: true" "$OPENSEARCH_DASHBOARD_YML"
  [ "$status" -eq 0 ]

  # Key remains block style (no single-line flow)
  run grep -Eq '^plugins\.security\.system_indices\.indices:\s*$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
  run grep -Eq '^plugins\.security\.system_indices\.indices:\s*\[' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -ne 0 ]

  # Existing item present once
  [ $(grep -Ec '^\s*-\s*"\.opendistro-alerting-config"$' "$OPENSEARCH_DASHBOARD_YML") -eq 1 ]
  # New items appended (allow quoted or unquoted)
  run grep -Eq '^\s*-\s*("|)\.plugins-ml-agent("|)$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
  run grep -Eq '^\s*-\s*("|)\.plugins-ml-config("|)$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
  run grep -Eq '^\s*-\s*("|)\.plugins-ml-connector("|)$' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
}

@test "system_indices: mixed styles (dest flow, new block) -> keep flow and append missing" {
  cat > "$OPENSEARCH_DASHBOARD_YML" <<'YML'
plugins.security.system_indices.indices: [".plugins-ml-model", ".plugins-ml-task", ".opendistro-alerting-config", ".opendistro-alerting-alert*", ".opendistro-anomaly-results*", ".opendistro-anomaly-detector*", ".opendistro-anomaly-checkpoints", ".opendistro-anomaly-detection-state", ".opendistro-reports-*", ".opensearch-notifications-*", ".opensearch-notebooks", ".opensearch-observability", ".opendistro-asynchronous-search-response*", ".replication-metadata-store"]
YML

  cat > "$OPENSEARCH_DASHBOARD_YML.dpkg-dist" <<'YML'
plugins.security.system_indices.indices:
  - ".plugins-ml-model"
  - .plugins-ml-agent
  - .plugins-ml-config
YML

  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"; [ "$status" -eq 0 ]
  # Remains flow-style
  run grep -Eq '^plugins\.security\.system_indices\.indices:\s*\[' "$OPENSEARCH_DASHBOARD_YML"; [ "$status" -eq 0 ]
  # Contains appended items exactly once
  COUNT=$(grep -o "\.plugins-ml-agent" "$OPENSEARCH_DASHBOARD_YML" | wc -l | tr -d ' ')
  [ "$COUNT" -eq 1 ]
}
