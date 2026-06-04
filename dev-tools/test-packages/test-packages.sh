#!/bin/sh
set -u

# Package name
PACKAGE=""
# Container name
CONTAINER_NAME="wazuh-dashboard"
# Files to check
FILES="/etc/wazuh-dashboard/opensearch_dashboards.yml /usr/share/wazuh-dashboard"
# Owner of the files
FILE_OWNER="wazuh-dashboard"
# Test mode flags
NEGATIVE_TEST=false
NEGATIVE_UNKNOWN_TEST=false
REINSTALL_TEST=false

# Remove container and image
clean() {
  # Only clean if the container exists (negative test may not create one)
  if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    docker stop $CONTAINER_NAME
    # This is done because in the construction of packages arm sometimes fails because it is not finished destroying the container and when trying to delete the image fails because it is in use.
    MAX_RETRIES=30
    RETRY_COUNT=0
    echo "Waiting for the container ($CONTAINER_NAME) to be removed"
    while docker ps -a --format "{{.Names}}" | grep $CONTAINER_NAME; do
      echo "The $(docker ps -a --format "{{.Names}}" | grep $CONTAINER_NAME) container has not been removed yet. Retry number $RETRY_COUNT."
      if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "WARNING: Maximum retries reached while waiting for container to stop"
        break
      fi
      sleep 2
      RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    echo "Container removed. Removing the image"
    docker rmi -f $CONTAINER_NAME
  fi
}

# Check if files exist and are owned by wazuh-dashboard
files_exist() {
  for FILE in $FILES; do
    if docker exec $CONTAINER_NAME ls $FILE >/dev/null 2>&1; then
      file_owner=$(docker exec $CONTAINER_NAME stat -c '%U' $FILE)
      if [ "$file_owner" != "$FILE_OWNER" ]; then
        echo "ERROR: $FILE is owned by $file_owner instead of $FILE_OWNER"
        clean
        exit 1
      fi
      echo "$FILE exist and is owned by $FILE_OWNER"
    else
      echo "ERROR: $FILE does not exist"
      clean
      exit 1
    fi
  done
}

# Check if opensearch_dashboards.yml is the same as the one in the package
check_opensearch_dashboard_yml() {
  docker cp ../../config/opensearch_dashboards.prod.yml $CONTAINER_NAME:/tmp/opensearch_dashboards.yml

  diff_opensearch_dashboard_yml=$(docker exec $CONTAINER_NAME diff /etc/wazuh-dashboard/opensearch_dashboards.yml /tmp/opensearch_dashboards.yml)

  if [ -n "$diff_opensearch_dashboard_yml" ]; then
    echo "ERROR: opensearch_dashboards.yml is not the same as the one in the package"
    echo $diff_opensearch_dashboard_yml
    clean
    exit 1
  fi
  echo $(docker exec $CONTAINER_NAME diff /etc/wazuh-dashboard/opensearch_dashboards.yml /tmp/opensearch_dashboards.yml)
  echo "opensearch_dashboards.yml is the same as the one in the package"
}

# Check if metadata is correct for deb packages
check_metadata_deb() {

  IFS='_' read -r -a arrayNameFile <<< "$PACKAGE"
  metadataVersion=$(docker exec $CONTAINER_NAME apt show wazuh-dashboard | grep Version | awk '{print $2}')
  metadataPackage=$(docker exec $CONTAINER_NAME apt show wazuh-dashboard | grep Package | awk '{print $2}')
  metadataStatus=$(docker exec $CONTAINER_NAME apt show wazuh-dashboard | grep Status)

  # Check if metadata is correct
  if [ "${arrayNameFile[1]}" != "$metadataVersion" ]; then
    echo "ERROR: metadata version is not the same as the one in the package"
    echo "metadata version: $metadataVersion"
    echo "package version: ${arrayNameFile[1]}"
    clean
    exit 1
  elif [ "${arrayNameFile[0]}" != "$metadataPackage" ]; then
    echo "ERROR: metadata package is not the same as the one in the package"
    echo "metadata package: $metadataPackage"
    echo "package package: ${arrayNameFile[0]}"
    clean
    exit 1
  elif [ "$metadataStatus" != "Status: install ok installed" ]; then
    echo "ERROR: metadata status is not 'Status: install ok installed'"
    echo "metadata status: $metadataStatus"
    clean
    exit 1
  fi

  echo "metadata version is correct: $metadataVersion"
  echo "metadata package is correct: $metadataPackage"
  echo "metadata status is $metadataStatus"
}

check_metadata_rpm() {
  metadataVersion=$(docker exec $CONTAINER_NAME rpm -q --qf '%{VERSION}-%{RELEASE}' wazuh-dashboard)
  metadataPackage=$(docker exec $CONTAINER_NAME rpm -q --qf '%{NAME}' wazuh-dashboard)

  # Check if metadata is correct
  if [[ $PACKAGE != *"$metadataVersion"* ]]; then
    echo "ERROR: metadata version is not the same as the one in the package"
    echo "metadata version: $metadataVersion"
    echo "package version: $PACKAGE"
    clean
    exit 1
  elif [[ $PACKAGE != "$metadataPackage"* ]]; then
    echo "ERROR: metadata package is not the same as the one in the package"
    echo "metadata package: $metadataPackage"
    echo "package package: $PACKAGE"
    clean
    exit 1
  fi

  echo "metadata version is correct: $metadataVersion"
  echo "metadata package is correct: $metadataPackage"
}

# Block-4x-install test: assert 5.x install is BLOCKED when 4.x is pre-installed
block_4x_install_test() {
  BUILD_LOG=$(mktemp)

  if [[ $PACKAGE == *".deb" ]]; then
    set +e
    docker build --build-arg PACKAGE="$PACKAGE" --build-arg BLOCK_4X_INSTALL=true -t "$CONTAINER_NAME" ./deb/ > "$BUILD_LOG" 2>&1
    BUILD_EXIT_CODE=$?
    set -e
  elif [[ $PACKAGE == *".rpm" ]]; then
    set +e
    docker build --build-arg PACKAGE="$PACKAGE" --build-arg BLOCK_4X_INSTALL=true -t "$CONTAINER_NAME" ./rpm/ > "$BUILD_LOG" 2>&1
    BUILD_EXIT_CODE=$?
    set -e
  else
    echo "ERROR: $PACKAGE is not a valid package (valid packages are .deb and .rpm)"
    rm -f "$BUILD_LOG"
    exit 1
  fi

  if [ "$BUILD_EXIT_CODE" -eq 0 ]; then
    echo "ERROR: Installation should have been blocked but succeeded"
    rm -f "$BUILD_LOG"
    exit 1
  fi

  if grep -F -q "ERROR: Direct upgrade from Wazuh dashboard" "$BUILD_LOG"; then
    BLOCK_MSG=$(grep -F 'ERROR: Direct upgrade from Wazuh dashboard' "$BUILD_LOG" | head -1 | sed 's/^ *#[0-9]* *[0-9.]* *//')
    echo "  $BLOCK_MSG"
  else
    echo "ERROR: Expected error message not found in build output"
    echo "--- Build output ---"
    cat "$BUILD_LOG"
    rm -f "$BUILD_LOG"
    exit 1
  fi

  echo "SUCCESS: 5.x installation correctly blocked when 4.x is installed"
  rm -f "$BUILD_LOG"
}

# Block-unknown-install test: assert 5.x install is BLOCKED when remnants exist but version is unknown
block_unknown_install_test() {
  BUILD_LOG=$(mktemp)

  if [[ $PACKAGE == *".deb" ]]; then
    set +e
    docker build --build-arg PACKAGE="$PACKAGE" --build-arg BLOCK_UNKNOWN_INSTALL=true -t "$CONTAINER_NAME" ./deb/ > "$BUILD_LOG" 2>&1
    BUILD_EXIT_CODE=$?
    set -e
  elif [[ $PACKAGE == *".rpm" ]]; then
    set +e
    docker build --build-arg PACKAGE="$PACKAGE" --build-arg BLOCK_UNKNOWN_INSTALL=true -t "$CONTAINER_NAME" ./rpm/ > "$BUILD_LOG" 2>&1
    BUILD_EXIT_CODE=$?
    set -e
  else
    echo "ERROR: $PACKAGE is not a valid package (valid packages are .deb and .rpm)"
    rm -f "$BUILD_LOG"
    exit 1
  fi

  if [ "$BUILD_EXIT_CODE" -eq 0 ]; then
    echo "ERROR: Installation should have been blocked but succeeded"
    rm -f "$BUILD_LOG"
    exit 1
  fi

  if grep -F -q "version could not be determined" "$BUILD_LOG"; then
    BLOCK_MSG=$(grep -F 'version could not be determined' "$BUILD_LOG" | head -1 | sed 's/^ *#[0-9]* *[0-9.]* *//')
    echo "  $BLOCK_MSG"
  else
    echo "ERROR: Expected error message not found in build output"
    echo "--- Build output ---"
    cat "$BUILD_LOG"
    rm -f "$BUILD_LOG"
    exit 1
  fi

  echo "SUCCESS: 5.x installation correctly blocked when previous install remnants exist with unknown version"
  rm -f "$BUILD_LOG"
}

# Reinstall test: assert 5.x install over 5.x succeeds (same-major reinstall)
same_major_reinstall_test() {
  if [[ $PACKAGE == *".deb" ]]; then
    docker build --build-arg PACKAGE="$PACKAGE" --build-arg ALLOW_SAME_MAJOR_REINSTALL=true -t "$CONTAINER_NAME" ./deb/ && \
    docker run -it --rm -d --name "$CONTAINER_NAME" "$CONTAINER_NAME" && \
    check_metadata_deb
  elif [[ $PACKAGE == *".rpm" ]]; then
    docker build --build-arg PACKAGE="$PACKAGE" --build-arg ALLOW_SAME_MAJOR_REINSTALL=true -t "$CONTAINER_NAME" ./rpm/ && \
    docker run -it --rm -d --name "$CONTAINER_NAME" "$CONTAINER_NAME" && \
    check_metadata_rpm
  else
    echo "ERROR: $PACKAGE is not a valid package (valid packages are .deb and .rpm)"
    exit 1
  fi

  echo "SUCCESS: 5.x reinstall over 5.x succeeded"
  files_exist
  check_opensearch_dashboard_yml
}

# Run test
test() {

  if [[ $PACKAGE == *".deb" ]]; then
    docker build --build-arg PACKAGE=$PACKAGE -t $CONTAINER_NAME ./deb/
    docker run -it --rm -d --name $CONTAINER_NAME $CONTAINER_NAME
    check_metadata_deb
  elif [[ $PACKAGE == *".rpm" ]]; then
    docker build --build-arg PACKAGE=$PACKAGE -t $CONTAINER_NAME ./rpm/
    docker run -it --rm -d --name $CONTAINER_NAME $CONTAINER_NAME
    check_metadata_rpm
  else
    echo "ERROR: $PACKAGE is not a valid package (valid packages are .deb and .rpm ))"
    exit 1
  fi

  files_exist

  check_opensearch_dashboard_yml
}

# Show help
help() {
  echo
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "    -p, --package <path>       Set Wazuh Dashboard rpm package name,which has to be in the <repository>/dev-tools/test-packages/<DISTRIBUTION>/ folder."
  echo "    --block-4x-install         Run block test: assert 5.x install is blocked when 4.x is pre-installed."
  echo "    --block-unknown-install    Run block test: assert 5.x install is blocked when remnants exist but version is unknown."
  echo "    --allow-same-major-reinstall Run reinstall test: assert 5.x reinstall over 5.x succeeds."
  echo "    -h, --help                 Show this help."
  echo
  exit $1
}

main() {
  while [ $# -gt 0 ]; do
    case "${1}" in
    "-h" | "--help")
      help 0
      ;;
    "-p" | "--package")
      if [ -n "${2}" ]; then
        PACKAGE="${2}"
        shift 2
      else
        help 1
      fi
      ;;
    "--block-4x-install")
      NEGATIVE_TEST=true
      shift
      ;;
    "--block-unknown-install")
      NEGATIVE_UNKNOWN_TEST=true
      shift
      ;;
    "--allow-same-major-reinstall")
      REINSTALL_TEST=true
      shift
      ;;
    *)
      help 1
      ;;
    esac
  done

  if [ -z "$PACKAGE" ] ; then
    help 1
  fi

  # Count how many test modes are active — only one allowed at a time
  MODE_COUNT=0
  [ "$NEGATIVE_TEST" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
  [ "$NEGATIVE_UNKNOWN_TEST" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
  [ "$REINSTALL_TEST" = true ] && MODE_COUNT=$((MODE_COUNT + 1))

  if [ "$MODE_COUNT" -gt 1 ]; then
    echo "ERROR: Only one test mode flag can be used at a time"
    exit 1
  fi

  if [ "$NEGATIVE_TEST" = true ]; then
    block_4x_install_test
  elif [ "$NEGATIVE_UNKNOWN_TEST" = true ]; then
    block_unknown_install_test
  elif [ "$REINSTALL_TEST" = true ]; then
    same_major_reinstall_test
  else
    test
  fi

  clean
}

main "$@"
