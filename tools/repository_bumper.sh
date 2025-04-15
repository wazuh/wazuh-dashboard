#!/bin/bash
#
# Wazuh Security Dashboards Plugin repository bumper (Pure Shell Version)
# This script automates version and stage bumping across the repository using only shell commands.

set -e

# --- Global Variables ---
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null)
DATE_TIME=$(date "+%Y-%m-%d_%H-%M-%S-%3N")
LOG_FILE="${SCRIPT_PATH}/repository_bumper_${DATE_TIME}.log"
VERSION_FILE="${REPO_PATH}/VERSION.json"
PACKAGE_JSON="${REPO_PATH}/package.json"
VERSION=""
REVISION="00"
CURRENT_VERSION=""
WAZUH_DASHBOARD_PLUGINS_WORKFLOW_FILE="${REPO_PATH}/.github/workflows/build_wazuh_dashboard_with_plugins.yml"

# --- Helper Functions ---

# Function to log messages
log() {
  local message="$1"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[${timestamp}] ${message}" | tee -a "$LOG_FILE"
}

# Function to show usage
usage() {
  echo "Usage: $0 --version VERSION --stage STAGE [--help]"
  echo ""
  echo "Parameters:"
  echo "  --version VERSION   Specify the version (e.g., 4.6.0)"
  echo "  --stage STAGE       Specify the stage (e.g., alpha0, beta1, rc2, etc.)"
  echo "  --help              Display this help message"
  echo ""
  echo "Example:"
  echo "  $0 --version 4.6.0 --stage alpha0"
  echo "  $0 --version 4.6.0 --stage beta1"
}

# --- Core Logic Functions ---

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --stage)
      STAGE="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      log "ERROR: Unknown option: $1" # Log error instead of just echo
      usage
      exit 1
      ;;
    esac
  done
}

# Function to validate input parameters
validate_input() {
  if [ -z "$VERSION" ]; then
    log "ERROR: Version parameter is required"
    usage
    exit 1
  fi
  if [ -z "$STAGE" ]; then
    log "ERROR: Stage parameter is required"
    usage
    exit 1
  fi
  if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log "ERROR: Version must be in the format x.y.z (e.g., 4.6.0)"
    exit 1
  fi
  if ! [[ $STAGE =~ ^[a-zA-Z]+[0-9]+$ ]]; then
    log "ERROR: Stage must be alphanumeric (e.g., alpha0, beta1, rc2)"
    exit 1
  fi
}

# Function to perform pre-update checks and gather initial data
pre_update_checks() {
  if [ ! -f "$VERSION_FILE" ]; then
    log "ERROR: Root VERSION.json not found at $VERSION_FILE"
    exit 1
  fi

  # Attempt to extract version from VERSION.json using sed
  log "Attempting to extract current version from $VERSION_FILE using sed..."
  CURRENT_VERSION=$(sed -n 's/^\s*"version"\s*:\s*"\([^"]*\)".*$/\1/p' "$VERSION_FILE" | head -n 1) # head -n 1 ensures only the first match is taken

  # Check if sed successfully extracted a version
  if [ -z "$CURRENT_VERSION" ]; then
    log "ERROR: Failed to extract 'version' from $VERSION_FILE using sed. Check file format or key presence."
    exit 1 # Exit if sed fails
  fi
  log "Successfully extracted version using sed: $CURRENT_VERSION"

  if [ "$CURRENT_VERSION" == "null" ]; then # Check specifically for "null" string if sed might output that
    log "ERROR: Could not read current version from $VERSION_FILE (value was 'null')"
    exit 1
  fi
  log "Current version detected in VERSION.json: $CURRENT_VERSION"

  # Attempt to extract stage from VERSION.json using sed
  log "Attempting to extract current stage from $VERSION_FILE using sed..."
  CURRENT_STAGE=$(sed -n 's/^\s*"stage"\s*:\s*"\([^"]*\)".*$/\1/p' "$VERSION_FILE" | head -n 1) # head -n 1 ensures only the first match is taken

  # Check if sed successfully extracted a stage
  if [ -z "$CURRENT_STAGE" ]; then
    log "ERROR: Failed to extract 'stage' from $VERSION_FILE using sed. Check file format or key presence."
    exit 1 # Exit if sed fails
  fi
  log "Successfully extracted stage using sed: $CURRENT_STAGE"

  if [ "$CURRENT_STAGE" == "null" ]; then # Check specifically for "null" string if sed might output that
    log "ERROR: Could not read current stage from $VERSION_FILE (value was 'null')"
    exit 1
  fi
  log "Current stage detected in VERSION.json: $CURRENT_STAGE"

  # Attempt to extract current revision from package.json using sed
  log "Attempting to extract current revision from $PACKAGE_JSON using sed..."
  CURRENT_REVISION=$(sed -n '/"wazuh": {/,/}/ s/^\s*"revision"\s*:\s*"\([^"]*\)".*$/\1/p' "$PACKAGE_JSON" | head -n 1)

  if [ -z "$CURRENT_REVISION" ]; then
    log "ERROR: Failed to extract 'revision' from $PACKAGE_JSON using sed. Check file format or key presence."
    exit 1
  fi
  log "Successfully extracted revision using sed: $CURRENT_REVISION"

  if [ "$CURRENT_REVISION" == "null" ]; then
    log "ERROR: Could not read current revision from $PACKAGE_JSON (value was 'null')"
    exit 1
  fi
  log "Current revision detected in package.json: $CURRENT_REVISION"

  log "Default revision set to: $REVISION" # Log default revision here
}

# Function to compare versions and determine revision
compare_versions_and_set_revision() {
  log "Comparing new version ($VERSION) with current version ($CURRENT_VERSION)..."

  # Split versions into parts using '.' as delimiter
  IFS='.' read -r -a NEW_VERSION_PARTS <<<"$VERSION"
  IFS='.' read -r -a CURRENT_VERSION_PARTS <<<"$CURRENT_VERSION"

  # Ensure both versions have 3 parts (Major.Minor.Patch)
  if [ ${#NEW_VERSION_PARTS[@]} -ne 3 ] || [ ${#CURRENT_VERSION_PARTS[@]} -ne 3 ]; then
    log "ERROR: Invalid version format detected during comparison. Both versions must be x.y.z."
    exit 1
  fi

  # Compare Major version
  if ((${NEW_VERSION_PARTS[0]} < ${CURRENT_VERSION_PARTS[0]})); then
    log "ERROR: New major version (${NEW_VERSION_PARTS[0]}) cannot be lower than current major version (${CURRENT_VERSION_PARTS[0]})."
    exit 1
  elif ((${NEW_VERSION_PARTS[0]} > ${CURRENT_VERSION_PARTS[0]})); then
    log "Version check passed: New version ($VERSION) is greater than current version ($CURRENT_VERSION) (Major increased)."
    REVISION="00" # Reset revision on major increase
  else
    # Major versions are equal, compare Minor version
    if ((${NEW_VERSION_PARTS[1]} < ${CURRENT_VERSION_PARTS[1]})); then
      log "ERROR: New minor version (${NEW_VERSION_PARTS[1]}) cannot be lower than current minor version (${CURRENT_VERSION_PARTS[1]}) when major versions are the same."
      exit 1
    elif ((${NEW_VERSION_PARTS[1]} > ${CURRENT_VERSION_PARTS[1]})); then
      log "Version check passed: New version ($VERSION) is greater than current version ($CURRENT_VERSION) (Minor increased)."
      REVISION="00" # Reset revision on minor increase
    else
      # Major and Minor versions are equal, compare Patch version
      if ((${NEW_VERSION_PARTS[2]} < ${CURRENT_VERSION_PARTS[2]})); then
        log "ERROR: New patch version (${NEW_VERSION_PARTS[2]}) cannot be lower than current patch version (${CURRENT_VERSION_PARTS[2]}) when major and minor versions are the same."
        exit 1
      elif ((${NEW_VERSION_PARTS[2]} > ${CURRENT_VERSION_PARTS[2]})); then
        log "Version check passed: New version ($VERSION) is greater than current version ($CURRENT_VERSION) (Patch increased)."
        REVISION="00" # Reset revision on patch increase
      else
        # Versions are identical (Major, Minor, Patch are equal)
        log "New version ($VERSION) is identical to current version ($CURRENT_VERSION). Incrementing revision."
        log "Attempting to extract current revision from $PACKAGE_JSON using sed (Note: This is fragile)"
        local current_revision_val=$(sed -n 's/^\s*"revision"\s*:\s*"\([^"]*\)".*$/\1/p' "$PACKAGE_JSON" | head -n 1)
        # Check if sed successfully extracted a revision
        if [ -z "$current_revision_val" ]; then
          log "ERROR: Failed to extract 'revision' from $PACKAGE_JSON using sed. Check file format or key presence."
          exit 1 # Exit if sed fails
        fi
        log "Successfully extracted revision using sed: $current_revision_val"
        if [ -z "$current_revision_val" ] || [ "$current_revision_val" == "null" ]; then
          log "ERROR: Could not read current revision from $PACKAGE_JSON"
          exit 1
        fi
        # Ensure CURRENT_REVISION is treated as a number (remove leading zeros for arithmetic if necessary, handle base 10)
        local current_revision_int=$((10#$current_revision_val))
        local new_revision_int=$((current_revision_int + 1))
        # Format back to two digits with leading zero
        REVISION=$(printf "%02d" "$new_revision_int")
        log "Current revision: $current_revision_val. New revision set to: $REVISION"
      fi
    fi
  fi
  log "Final revision determined: $REVISION"
}

# Function to update VERSION.json
update_root_version_json() {
  if [ -f "$VERSION_FILE" ]; then
    log "Processing $VERSION_FILE"
    # Update version and revision in VERSION.json
    local modified=false

    # Update version in VERSION.json
    if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
      sed -i "s/^\s*\"version\"\s*:\s*\"[^\"]*\"/  \"version\": \"$VERSION\"/" "$VERSION_FILE"
      modified=true
    fi

    # Update stage in VERSION.json
    if [[ "$CURRENT_STAGE" != "$STAGE" ]]; then
      sed -i "s/^\s*\"stage\"\s*:\s*\"[^\"]*\"/  \"stage\": \"$STAGE\"/" "$VERSION_FILE"
      modified=true
    fi

    if [[ $modified == true ]]; then
      log "Successfully updated $VERSION_FILE with new version: $VERSION and stage: $STAGE"
    fi
  else
    log "WARNING: $VERSION_FILE not found. Skipping update."
  fi
}

update_package_json() {
  if [ -f "$PACKAGE_JSON" ]; then
    log "Processing $PACKAGE_JSON"
    local modified=false
    # Update version and revision in package.json
    # "wazuh": {
    #   "version": "4.13.0",
    #   "revision": "00"
    # },
    # Update version and revision in package.json using the structure above
    # Use sed with address range to target lines within the "wazuh": { ... } block
    # Update version in package.json
    if [[ "$CURRENT_VERSION" != "$VERSION" ]]; then
      log "Attempting to update version to $VERSION within 'wazuh' object in $PACKAGE_JSON"
      # Note: This sed command assumes a specific formatting and might be fragile.
      # It looks for the block starting with a line containing "wazuh": { and ending with the next line containing only }
      # Within that block, it replaces the value on the line starting with "version":
      sed -i "/\"wazuh\": {/,/}/ s/^\(\s*\"version\"\s*:\s*\)\"[^\"]*\"/\1\"$VERSION\"/" "$PACKAGE_JSON"
      modified=true
    fi

    # Update revision in package.json
    if [[ "$CURRENT_REVISION" != "$REVISION" ]]; then
      log "Attempting to update revision to $REVISION within 'wazuh' object in $PACKAGE_JSON"
      # Similar sed command for the revision line within the same block
      sed -i "/\"wazuh\": {/,/}/ s/^\(\s*\"revision\"\s*:\s*\)\"[^\"]*\"/\1\"$REVISION\"/" "$PACKAGE_JSON"
      modified=true
    fi

    if [[ $modified == true ]]; then
      log "Successfully updated $PACKAGE_JSON with new version: $VERSION and revision: $REVISION"
    fi
  else
    log "WARNING: $PACKAGE_JSON not found. Skipping update."
  fi
}

# Function to update CHANGELOG.md
update_changelog() {
  log "Updating CHANGELOG.md..."
  local changelog_file="${REPO_PATH}/CHANGELOG.md"

  # Extract OpenSearch Dashboards version from package.json
  # Attempt to extract OpenSearch Dashboards version using sed (WARNING: Fragile!)
  # This assumes "pluginPlatform": { ... "version": "x.y.z" ... } structure
  # It looks for the block starting with "pluginPlatform": { and ending with }
  # Within that block, it finds the line starting with "version": "..." and extracts the value.
  # This is significantly less reliable than using jq.
  log "Attempting to extract .version from $VERSION_FILE using sed (Note: This is fragile)"
  # Extract OpenSearch Dashboards version from package.json (first occurrence of "version")
  OPENSEARCH_VERSION=$(sed -n 's/^\s*"version"\s*:\s*"\([^"]*\)".*$/\1/p' "$PACKAGE_JSON" | head -n 1)
  if [ -z "$OPENSEARCH_VERSION" ] || [ "$OPENSEARCH_VERSION" == "null" ]; then
    log "ERROR: Could not extract pluginPlatform.version from $PACKAGE_JSON for changelog"
    exit 1
  fi
  log "Detected OpenSearch Dashboards version for changelog: $OPENSEARCH_VERSION"

  # Construct the new changelog entry
  # Note: Using printf for better handling of newlines and potential special characters
  # Use the calculated REVISION variable here
  # Prepare the header to search for
  local changelog_header="## Wazuh dashboard v${VERSION} - OpenSearch Dashboards ${OPENSEARCH_VERSION} - Revision "
  local changelog_header_regex="^${changelog_header}[0-9]+"

  # Check if an entry for this version and OpenSearch version already exists
  if grep -qE "$changelog_header_regex" "$changelog_file"; then
    log "Changelog entry for this version and OpenSearch Dashboards version exists. Updating revision only."
    # Use sed to update only the revision number in the header
    sed -i -E "s|(${changelog_header_regex})|${changelog_header}${REVISION}|" "$changelog_file" &&
      log "CHANGELOG.md revision updated successfully." || {
      log "ERROR: Failed to update revision in $changelog_file"
      exit 1
    }
  else
    log "No existing changelog entry for this version and OpenSearch Dashboards version. Inserting new entry."
    local new_entry
    new_entry=$(printf "${changelog_header}%s\n\n### Added\n\n- Support for Wazuh %s\n" "$REVISION" "$VERSION")

    # Use awk to insert the new entry after the title and description (lines 1-4)
    awk -v entry="$new_entry" '
    NR == 1 { print; next } # Print line 1 (# Change Log)
    NR == 2 { print; next } # Print line 2 (blank)
    NR == 3 { print; next } # Print line 3 (description)
    NR == 4 { print; printf "%s\n\n", entry; next } # Print line 4 (blank) and insert entry
    { print } # Print the rest of the lines starting from line 5
    ' "$changelog_file" >temp_changelog && mv temp_changelog "$changelog_file" || {
      log "ERROR: Failed to update $changelog_file"
      rm -f temp_changelog # Clean up temp file on error
      exit 1
    }
    log "CHANGELOG.md updated successfully."
  fi
}

update_build_workflow() {
  log "Updating $(basename $WAZUH_DASHBOARD_PLUGINS_WORKFLOW_FILE)..."

  if [ -f "$WAZUH_DASHBOARD_PLUGINS_WORKFLOW_FILE" ]; then
    local modified=false
    # Update all occurrences of yml@x.y.z with yml@$VERSION-$STAGE
    sed -i -E "s/(\.yml@)v?[0-9]+\.[0-9]+\.[0-9]+(-[a-z]+[0-9]+)?/\1v${VERSION}-${STAGE}/g" "$WAZUH_DASHBOARD_PLUGINS_WORKFLOW_FILE" && modified=true

    if [[ $modified == true ]]; then
      log "Successfully updated yml@v${VERSION}-${STAGE} in $(basename $WAZUH_DASHBOARD_PLUGINS_WORKFLOW_FILE)"
    fi
  fi
}

# --- Main Execution ---
main() {
  # Initialize log file
  touch "$LOG_FILE"
  log "Starting repository bump process"

  # Check if inside a git repository early
  if [ -z "$REPO_PATH" ]; then
    # Use log function for consistency, redirect initial error to stderr
    log "ERROR: Failed to determine repository root. Ensure you are inside the git repository." >&2
    exit 1
  fi
  log "Repository path: $REPO_PATH"

  # Parse and validate arguments
  parse_arguments "$@"
  validate_input
  log "Version: $VERSION"
  log "Stage: $STAGE"

  # Perform pre-update checks
  pre_update_checks

  # Compare versions and determine revision
  compare_versions_and_set_revision

  # Start file modifications
  log "Starting file modifications..."

  update_root_version_json
  update_package_json
  update_changelog
  update_build_workflow

  log "File modifications completed."
  log "Repository bump completed successfully. Log file: $LOG_FILE"
  exit 0
}

# Execute main function with all script arguments
main "$@"
