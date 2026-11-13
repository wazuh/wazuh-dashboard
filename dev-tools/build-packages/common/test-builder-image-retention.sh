#!/bin/bash

# Tests builder-image-retention.jq, the filter the builder images cleanup
# workflow uses to pick the ghcr versions to delete.
#
# Usage:
#   bash dev-tools/build-packages/common/test-builder-image-retention.sh
#
# Exits non-zero when a case doesn't select exactly the expected versions.

set -euo pipefail

filter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/builder-image-retention.jq"
failures=0

# check <name> <expected lines> <versions JSON>
# Compares the "<id>\t<reason>" lines selected by the filter with the expected
# ones, ignoring their order.
check() {
  local name="$1"
  local expected="$2"
  local versions="$3"
  local actual

  if ! actual="$(jq -r -f "${filter}" <<<"${versions}" 2>&1)"; then
    echo "FAIL: ${name}: the filter failed: ${actual}"
    failures=$((failures + 1))
    return
  fi

  actual="$(sort <<<"${actual}")"
  expected="$(sort <<<"${expected}")"
  if [ "${actual}" = "${expected}" ]; then
    echo "ok: ${name}"
  else
    echo "FAIL: ${name}"
    echo "  expected:"
    sed 's/^/    /' <<<"${expected}"
    echo "  actual:"
    sed 's/^/    /' <<<"${actual}"
    failures=$((failures + 1))
  fi
}

tab=$'\t'

# Every active branch has its own version but the same Dockerfile.
check "4 branches with the same hash: nothing deleted" "" '[
  {"id": 1, "created_at": "2026-11-01T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-aaaaaaaaaaaa"]}}},
  {"id": 2, "created_at": "2026-11-02T00:00:00Z", "metadata": {"container": {"tags": ["5.0.1-aaaaaaaaaaaa"]}}},
  {"id": 3, "created_at": "2026-11-03T00:00:00Z", "metadata": {"container": {"tags": ["5.1.0-aaaaaaaaaaaa"]}}},
  {"id": 4, "created_at": "2026-11-04T00:00:00Z", "metadata": {"container": {"tags": ["6.0.0-aaaaaaaaaaaa"]}}}
]'

check "a branch with 3 successive hashes: the 2 oldest deleted" \
  "10${tab}superseded: 5.0.0-111111111111
11${tab}superseded: 5.0.0-222222222222" '[
  {"id": 10, "created_at": "2026-11-01T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-111111111111"]}}},
  {"id": 11, "created_at": "2026-11-02T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-222222222222"]}}},
  {"id": 12, "created_at": "2026-11-03T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-333333333333"]}}},
  {"id": 13, "created_at": "2026-11-01T12:00:00Z", "metadata": {"container": {"tags": ["5.0.1-111111111111"]}}}
]'

check "a version tagged for 2 prefixes: kept while it is the newest for one" "" '[
  {"id": 20, "created_at": "2026-11-01T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-aaaaaaaaaaaa", "5.0.1-aaaaaaaaaaaa"]}}},
  {"id": 21, "created_at": "2026-11-02T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-bbbbbbbbbbbb"]}}}
]'

check "a version tagged for 2 prefixes: deleted once superseded for both" \
  "20${tab}superseded: 5.0.0-aaaaaaaaaaaa,5.0.1-aaaaaaaaaaaa" '[
  {"id": 20, "created_at": "2026-11-01T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-aaaaaaaaaaaa", "5.0.1-aaaaaaaaaaaa"]}}},
  {"id": 21, "created_at": "2026-11-02T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-bbbbbbbbbbbb"]}}},
  {"id": 22, "created_at": "2026-11-03T00:00:00Z", "metadata": {"container": {"tags": ["5.0.1-cccccccccccc"]}}}
]'

check "untagged versions: deleted" \
  "30${tab}untagged
31${tab}untagged" '[
  {"id": 30, "created_at": "2026-11-01T00:00:00Z", "metadata": {"container": {"tags": []}}},
  {"id": 31, "created_at": "2026-11-02T00:00:00Z", "metadata": {"container": {}}},
  {"id": 32, "created_at": "2026-11-03T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-aaaaaaaaaaaa"]}}}
]'

# Only <prefix>-<12 lowercase hex> tags are managed: a version with any other
# tag was pushed by hand or by another tool and is never touched.
check "tags in another format: kept" "" '[
  {"id": 40, "created_at": "2026-11-01T00:00:00Z", "metadata": {"container": {"tags": ["latest"]}}},
  {"id": 41, "created_at": "2026-11-02T00:00:00Z", "metadata": {"container": {"tags": ["latest", "5.0.0-111111111111"]}}},
  {"id": 42, "created_at": "2026-11-03T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-ABCDEFABCDEF"]}}},
  {"id": 43, "created_at": "2026-11-04T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-abc"]}}},
  {"id": 44, "created_at": "2026-11-05T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-222222222222"]}}}
]'

check "no versions: nothing deleted" "" '[]'

# Known edge case: when a Dockerfile is reverted to an older content, its tag
# already exists, so the upload doesn't push it again and the newer tag stays
# the newest for that version. The cleanup then deletes the tag the branch
# uses again, and package builds fall back to building the image locally
# until the Dockerfile changes.
check "a Dockerfile reverted to an older hash: the older, in-use tag deleted" \
  "50${tab}superseded: 5.0.0-aaaaaaaaaaaa" '[
  {"id": 50, "created_at": "2026-11-01T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-aaaaaaaaaaaa"]}}},
  {"id": 51, "created_at": "2026-11-02T00:00:00Z", "metadata": {"container": {"tags": ["5.0.0-bbbbbbbbbbbb"]}}}
]'

if [ "${failures}" -ne 0 ]; then
  echo "${failures} case(s) failed"
  exit 1
fi
echo "All cases passed"
