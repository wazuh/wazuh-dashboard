#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  echo "bats not found. Install with one of:" >&2
  echo "  - Homebrew: brew install bats-core" >&2
  echo "  - npm: npm i -g bats" >&2
  echo "  - GitHub: https://github.com/bats-core/bats-core" >&2
  exit 127
fi

exec bats "$ROOT_DIR/tests" "$@"

