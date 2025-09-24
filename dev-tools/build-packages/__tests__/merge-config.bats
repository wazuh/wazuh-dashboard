#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MERGE_SCRIPT="$REPO_DIR/config/merge-config.sh"
  TMPDIR_TEST=$(mktemp -d)
  CONFIG_DIR="$TMPDIR_TEST/etc/wazuh-dashboard"
  mkdir -p "$CONFIG_DIR"
  OPENSEARCH_DASHBOARD_YML="$CONFIG_DIR/opensearch_dashboards.yml"
  FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

parse_fixture_metadata() {
  local line key value
  while IFS= read -r line; do
    key=${line%% *}
    value=${line#* }
    case "$key" in
      DEFAULT_SUFFIX) DEFAULT_SUFFIX="$value" ;;
      RUN_TWICE) RUN_TWICE="$value" ;;
      EXPECT_STATUS) EXPECT_STATUS="$value" ;;
      EXPECT_PACKAGED_REMOVED) EXPECT_PACKAGED_REMOVED="$value" ;;
      EXPECT_MODE) EXPECT_MODE="$value" ;;
    esac
  done <<EOF
$(awk '
  /^metadata:/ {in_meta=1; next}
  in_meta && /^[^[:space:]].*:/{in_meta=0}
  in_meta {
    if (match($0, /^[[:space:]]+([^:]+):[[:space:]]*(.*)$/, a)) {
      key=a[1]; val=a[2];
      gsub(/^"|"$/, "", val);
      if (val == "") { val="" }
      printf "%s %s\n", key, val;
    }
  }
' "$FIXTURE_FILE")
EOF
}

section_to_file() {
  local key="$1" dest="$2" presence_var="$3"
  local section section_type body
  section=$(awk -v key="$key" '
    BEGIN {capture=0}
    $0 ~ "^"key":" {
      capture=1
      line=$0
      sub("^" key ":", "", line)
      sub(/^[[:space:]]*/, "", line)
      if (line == "~") { print "__TYPE__ NULL"; exit }
      if (line == "\"\"") { print "__TYPE__ EMPTY"; exit }
      if (line == "" || line == "|-" || line == "|") { print "__TYPE__ BLOCK"; next }
      print "__TYPE__ INLINE"
      print line
      exit
    }
    capture {
      if (/^[^[:space:]].*:/) { exit }
      sub(/^[[:space:]]{2}/, "", $0)
      print $0
    }
  ' "$FIXTURE_FILE")

  if [ -z "$section" ]; then
    eval "$presence_var=0"
    rm -f "$dest"
    return
  fi

  section_type=$(printf '%s
' "$section" | head -n1 | awk '{print $2}')
  body=$(printf '%s
' "$section" | tail -n +2)

  case "$section_type" in
    NULL)
      eval "$presence_var=0"
      rm -f "$dest"
      ;;
    EMPTY)
      : > "$dest"
      eval "$presence_var=1"
      ;;
    INLINE)
      printf '%s
' "$body" > "$dest"
      eval "$presence_var=1"
      ;;
    BLOCK)
      if [ -n "$body" ]; then
        printf '%s\n' "$body" > "$dest"
      else
        : > "$dest"
      fi
      eval "$presence_var=1"
      ;;
    *)
      eval "$presence_var=0"
      rm -f "$dest"
      ;;
  esac
}

prepare_fixture() {
  FIXTURE_NAME="$1"
  FIXTURE_FILE="$FIXTURES_DIR/$FIXTURE_NAME.yml"
  [ -f "$FIXTURE_FILE" ]

  DEFAULT_SUFFIX=""
  RUN_TWICE=0
  EXPECT_STATUS=0
  EXPECT_PACKAGED_REMOVED=""
  EXPECT_MODE=""

  parse_fixture_metadata

  RUN_TWICE=${RUN_TWICE:-0}
  EXPECT_STATUS=${EXPECT_STATUS:-0}

  section_to_file "defined_by_user" "$OPENSEARCH_DASHBOARD_YML" DEFINED_PRESENT

  local defaults_tmp="$TMPDIR_TEST/defaults.yml"
  section_to_file "defaults" "$defaults_tmp" DEFAULTS_PRESENT
  if [ "$DEFAULTS_PRESENT" -eq 1 ]; then
    DEFAULT_SUFFIX=${DEFAULT_SUFFIX:-rpmnew}
    PACKAGED_PATH="$OPENSEARCH_DASHBOARD_YML.$DEFAULT_SUFFIX"
    cp "$defaults_tmp" "$PACKAGED_PATH"
  else
    PACKAGED_PATH=""
  fi

  EXPECTED_PATH="$TMPDIR_TEST/expected.yml"
  section_to_file "expected" "$EXPECTED_PATH" EXPECTED_PRESENT
  if [ "$EXPECTED_PRESENT" -eq 0 ]; then
    rm -f "$EXPECTED_PATH"
  fi

  if [ -z "$EXPECT_PACKAGED_REMOVED" ] && [ -n "$PACKAGED_PATH" ]; then
    case "$DEFAULT_SUFFIX" in
      rpmnew|dpkg-dist|ucf-dist)
        EXPECT_PACKAGED_REMOVED=0
        ;;
      *)
        EXPECT_PACKAGED_REMOVED=1
        ;;
    esac
  fi

  if [ -z "$EXPECT_DESTINATION_PRESENT" ]; then
    if [ "$EXPECTED_PRESENT" -eq 1 ]; then
      EXPECT_DESTINATION_PRESENT=1
    else
      EXPECT_DESTINATION_PRESENT=0
    fi
  fi
}

sanitize_config() {
  local src="$1" dest="$2"
  sed \
    -e '/^# --- Added new default settings/d' \
    -e 's/# --- Added new default settings.*$//' \
    "$src" > "$dest"
  local content
  content=$(cat "$dest")
  printf '%s' "$content" > "$dest"
}

merge_once() {
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  echo "$output" >&3
  [ "$status" -eq "$EXPECT_STATUS" ]
}

assert_snapshot() {
  if [ "$EXPECT_DESTINATION_PRESENT" -eq 1 ]; then
    [ -f "$OPENSEARCH_DASHBOARD_YML" ]
    if [ "$EXPECTED_PRESENT" -eq 1 ]; then
      local sanitized_expected sanitized_actual
      sanitized_expected=$(mktemp "$TMPDIR_TEST/expected.XXXXXX")
      sanitized_actual=$(mktemp "$TMPDIR_TEST/actual.XXXXXX")
      sanitize_config "$EXPECTED_PATH" "$sanitized_expected"
      sanitize_config "$OPENSEARCH_DASHBOARD_YML" "$sanitized_actual"
      run diff -u "$sanitized_expected" "$sanitized_actual"
      echo "$output" >&3
      [ "$status" -eq 0 ]
    fi
  else
    [ ! -f "$OPENSEARCH_DASHBOARD_YML" ]
  fi
}

assert_packaged_file() {
  if [ -n "$PACKAGED_PATH" ] && [ -n "$EXPECT_PACKAGED_REMOVED" ]; then
    if [ "$EXPECT_PACKAGED_REMOVED" -eq 1 ]; then
      [ ! -f "$PACKAGED_PATH" ]
    else
      [ -f "$PACKAGED_PATH" ]
    fi
  fi
}

assert_mode() {
  if [ -n "$EXPECT_MODE" ] && [ -f "$OPENSEARCH_DASHBOARD_YML" ]; then
    PERM=$(stat -c %a "$OPENSEARCH_DASHBOARD_YML" 2>/dev/null || stat -f %Lp "$OPENSEARCH_DASHBOARD_YML")
    [ "$PERM" = "$EXPECT_MODE" ]
  fi
}

run_fixture_case() {
  prepare_fixture "$1"

  merge_once
  if [ "$RUN_TWICE" -eq 1 ]; then
    merge_once
  fi

  assert_packaged_file
  assert_mode
  assert_snapshot
}

@test "no new config file: script exits quietly and leaves file untouched" {
  run_fixture_case "no_new_config"
}

@test "rpmnew: appends only missing keys and removes .rpmnew" {
  run_fixture_case "rpmnew_append_missing"
}

@test "dpkg-dist: preserves existing keys and adds only missing ones" {
  run_fixture_case "dpkg_dist_preserves_existing"
}

@test ".dpkg-new: supported alias file name" {
  run_fixture_case "dpkg_new_alias"
}

@test "custom user config: keep existing values, add only missing defaults" {
  run_fixture_case "custom_user_config"
}

@test "whitespace/comments: existing key not duplicated despite formatting differences" {
  run_fixture_case "whitespace_existing_key"
}

@test "commented-out existing key should still be added as active setting" {
  run_fixture_case "commented_existing_key"
}

@test "partial overlap: multiple defaults provided, only absent keys added" {
  run_fixture_case "partial_overlap_add_missing"
}

@test "nested block default (.rpmnew): copy entire block when top-level key missing" {
  run_fixture_case "nested_block_from_defaults"
}

@test "nested block present in active: do not duplicate top-level key" {
  run_fixture_case "nested_block_existing"
}

@test "deep merge: add missing nested block under existing top-level" {
  run_fixture_case "deep_merge_add_block"
}

@test "deep merge: add missing leaf under existing nested object" {
  run_fixture_case "deep_merge_add_leaf"
}

@test "deep merge: no change if nested leaf already present" {
  run_fixture_case "deep_merge_no_change"
}

@test "edge: empty .rpmnew stays in place and no changes applied" {
  run_fixture_case "empty_rpmnew_preserved"
}

@test "edge: target missing but .rpmnew exists -> no action and .rpmnew remains" {
  run_fixture_case "target_missing_rpmnew_stays"
}

@test "block list merge: append missing items, preserve '-' style" {
  run_fixture_case "block_list_preserve_style"
}

@test "mixed styles: dest flow [], new block '-' -> keep flow and append missing" {
  run_fixture_case "mixed_styles_dest_flow"
}

@test "mixed styles: dest block '-', new flow [] -> keep block and append missing" {
  run_fixture_case "mixed_styles_dest_block"
}

@test "edge: malformed .rpmnew does not crash and packaged file remains" {
  run_fixture_case "malformed_rpmnew_preserved"
}

@test "edge: commented new block is ignored" {
  run_fixture_case "commented_block_ignored"
}

@test "edge: idempotent nested injection when rerun" {
  run_fixture_case "idempotent_nested_injection"
}

@test "post-install: add new default setting if missing" {
  run_fixture_case "post_install_add_missing"
}

@test "post-install: nothing to add when user already has all settings" {
  run_fixture_case "post_install_no_changes"
}

@test "inline array merge: append missing values for plugins.security.system_indices.indices" {
  run_fixture_case "inline_array_merge_append"
}

@test "inline array merge: idempotent on rerun (no duplicates)" {
  run_fixture_case "inline_array_merge_idempotent"
}

@test "system_indices: block list merge preserves '-' and appends missing (new flow style)" {
  run_fixture_case "system_indices_block_list_preserve"
}

@test "system_indices: mixed styles (dest flow, new block) -> keep flow and append missing" {
  run_fixture_case "system_indices_mixed_styles_flow_dest"
}

@test "backup is created alongside destination and packaged defaults are preserved" {
  fake_bin="$TMPDIR_TEST/fake_bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' "20250924T135307Z"
EOF
  chmod +x "$fake_bin/date"

  local PATH="$fake_bin:$PATH"

  cat > "$OPENSEARCH_DASHBOARD_YML" <<'EOF'
server.host: 0.0.0.0
EOF

  cp "$OPENSEARCH_DASHBOARD_YML" "$OPENSEARCH_DASHBOARD_YML.rpmnew"
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]

  mapfile -t backups < <(find "$CONFIG_DIR" -maxdepth 1 -type f -name "$(basename "$OPENSEARCH_DASHBOARD_YML").bak.*" | sort)
  [ "${#backups[@]}" -eq 1 ]
  backup1="${backups[0]}"
  [[ "$backup1" == ${OPENSEARCH_DASHBOARD_YML}.bak.* ]]

  cp "$OPENSEARCH_DASHBOARD_YML" "$OPENSEARCH_DASHBOARD_YML.rpmnew"
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [ -f "$OPENSEARCH_DASHBOARD_YML.rpmnew" ]

  mapfile -t backups_after < <(find "$CONFIG_DIR" -maxdepth 1 -type f -name "$(basename "$OPENSEARCH_DASHBOARD_YML").bak.*" | sort)
  [ "${#backups_after[@]}" -eq 2 ]
  [[ -f "$backup1" ]]
  [[ "${backups_after[0]}" == ${OPENSEARCH_DASHBOARD_YML}.bak.* ]]
  [[ "${backups_after[1]}" == ${OPENSEARCH_DASHBOARD_YML}.bak.* ]]
}
