#!/usr/bin/env sh
#
# Check Prettier formatting on the given files, skipping the ones that already
# fail the check at <base-ref>.
#
# A change has to leave the files it adds formatted, and it must not take a file
# that was formatted and leave it unformatted. It is not responsible for the
# drift it inherits. Demanding a whole-file reformat over a few changed lines
# rewrites code we carry from OpenSearch Dashboards, and every rewritten file
# becomes a conflict in the next upward merge or cherry-pick between version
# branches. Upstream does not run Prettier over its own repositories, so that
# drift is permanent and there is nothing to align to.
#
# Usage:
#   scripts/prettier-check-changed.sh <base-ref> [file...]
#
# CI passes origin/$GITHUB_BASE_REF. The pre-commit hook passes HEAD, and
# lint-staged appends absolute paths, which are normalized below.
# With no files, it succeeds.

set -eu

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <base-ref> [file...]" >&2
  exit 2
fi

BASE_REF="$1"
shift

if [ "$#" -eq 0 ]; then
  echo "No files to check."
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
PRETTIER="${REPO_ROOT}/node_modules/.bin/prettier"

if [ ! -x "${PRETTIER}" ]; then
  echo "Prettier not found at ${PRETTIER}. Run the install step first." >&2
  exit 2
fi

FILES=""
for f in "$@"; do
  case "${f}" in
    "${REPO_ROOT}/"*) f="${f#"${REPO_ROOT}/"}" ;;
  esac
  FILES="${FILES} ${f}"
done

# The base versions go in a throwaway tree at the same relative paths, next to a
# copy of the Prettier configuration, so both runs resolve the same options and
# the same ignore list.
BASE_TREE=$(mktemp -d)
trap 'rm -rf "${BASE_TREE}"' EXIT

for cfg in .prettierrc .prettierignore; do
  if [ -f "${REPO_ROOT}/${cfg}" ]; then
    cp "${REPO_ROOT}/${cfg}" "${BASE_TREE}/${cfg}"
  fi
done

BASE_FILES=""
for f in ${FILES}; do
  if git cat-file -e "${BASE_REF}:${f}" 2>/dev/null; then
    mkdir -p "${BASE_TREE}/$(dirname "${f}")"
    git show "${BASE_REF}:${f}" > "${BASE_TREE}/${f}"
    BASE_FILES="${BASE_FILES} ${f}"
  fi
done

# --list-different exits non-zero when it finds something, which is the normal
# case here, so its status is not an error.
SKIPPED=""
if [ -n "${BASE_FILES}" ]; then
  cd "${BASE_TREE}"
  # shellcheck disable=SC2086  # the file list has to split into arguments
  SKIPPED=$("${PRETTIER}" ${BASE_FILES} --list-different --ignore-unknown 2>/dev/null || true)
  cd "${REPO_ROOT}"
fi

TO_CHECK=""
for f in ${FILES}; do
  if printf '%s\n' "${SKIPPED}" | grep -qxF -- "${f}"; then
    continue
  fi
  TO_CHECK="${TO_CHECK} ${f}"
done

if [ -n "${SKIPPED}" ]; then
  echo "Already unformatted on ${BASE_REF}, not checked:"
  printf '%s\n' "${SKIPPED}" | sed 's/^/  /'
fi

if [ -z "${TO_CHECK}" ]; then
  echo "Nothing left to check."
  exit 0
fi

echo "Checking:"
# shellcheck disable=SC2086  # the file list has to split into arguments
for f in ${TO_CHECK}; do
  echo "  ${f}"
done

# shellcheck disable=SC2086  # the file list has to split into arguments
"${PRETTIER}" ${TO_CHECK} --check --ignore-unknown
