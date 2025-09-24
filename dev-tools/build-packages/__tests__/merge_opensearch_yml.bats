#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MERGE_SCRIPT="$REPO_DIR/config/merge_opensearch_yml.sh"
  TMPDIR_TEST=$(mktemp -d)
  CONFIG_DIR="$TMPDIR_TEST/etc/wazuh-dashboard"
  mkdir -p "$CONFIG_DIR"
  OPENSEARCH_DASHBOARD_YML="$CONFIG_DIR/opensearch_dashboards.yml"
  FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

prepare_fixture() {
  FIXTURE_NAME="$1"
  FIXTURE_DIR="$FIXTURES_DIR/$FIXTURE_NAME"
  [ -d "$FIXTURE_DIR" ]

  DEFAULT_SUFFIX=""
  RUN_TWICE=0
  EXPECT_STATUS=0
  EXPECT_PACKAGED_REMOVED=""
  EXPECT_DESTINATION_PRESENT=""
  EXPECT_MODE=""

  if [ -f "$FIXTURE_DIR/metadata.sh" ]; then
    # shellcheck disable=SC1090
    . "$FIXTURE_DIR/metadata.sh"
  fi

  if [ -f "$FIXTURE_DIR/defined_by_user.yml" ]; then
    cp "$FIXTURE_DIR/defined_by_user.yml" "$OPENSEARCH_DASHBOARD_YML"
  else
    rm -f "$OPENSEARCH_DASHBOARD_YML"
  fi

  if [ -f "$FIXTURE_DIR/defaults.yml" ]; then
    DEFAULT_SUFFIX="${DEFAULT_SUFFIX:-rpmnew}"
    PACKAGED_PATH="$OPENSEARCH_DASHBOARD_YML.$DEFAULT_SUFFIX"
    cp "$FIXTURE_DIR/defaults.yml" "$PACKAGED_PATH"
  else
    PACKAGED_PATH=""
  fi

  EXPECTED_PATH="$FIXTURE_DIR/expected.yml"
  if [ -z "$EXPECT_DESTINATION_PRESENT" ]; then
    if [ -f "$EXPECTED_PATH" ]; then
      EXPECT_DESTINATION_PRESENT=1
    else
      EXPECT_DESTINATION_PRESENT=0
    fi
  fi

  if [ -z "$EXPECT_PACKAGED_REMOVED" ] && [ -n "$PACKAGED_PATH" ]; then
    EXPECT_PACKAGED_REMOVED=1
  fi
}

merge_once() {
  run bash "$MERGE_SCRIPT" --config-dir "$CONFIG_DIR"
  echo "$output" >&3
  [ "$status" -eq "$EXPECT_STATUS" ]
}

assert_snapshot() {
  if [ "$EXPECT_DESTINATION_PRESENT" -eq 1 ]; then
    [ -f "$OPENSEARCH_DASHBOARD_YML" ]
    if [ -f "$EXPECTED_PATH" ]; then
      local sanitized_expected sanitized_actual
      sanitized_expected=$(mktemp "$TMPDIR_TEST/expected.XXXXXX")
      sanitized_actual=$(mktemp "$TMPDIR_TEST/actual.XXXXXX")
      sed '/^# --- Added new default settings/d' "$EXPECTED_PATH" > "$sanitized_expected"
      sed '/^# --- Added new default settings/d' "$OPENSEARCH_DASHBOARD_YML" > "$sanitized_actual"
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

@test "edge: empty .rpmnew is removed and no changes applied" {
  run_fixture_case "empty_rpmnew_removed"
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

@test "edge: malformed .rpmnew does not crash and removes packaged file" {
  run_fixture_case "malformed_rpmnew_removed"
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
