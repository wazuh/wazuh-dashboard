#!/usr/bin/env bash
set -euo pipefail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/tests/test.yml"

# Detect docker compose
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "Docker Compose is required (docker compose or docker-compose)." >&2
  exit 127
fi

"${COMPOSE[@]}" -f "$COMPOSE_FILE" build --pull
"${COMPOSE[@]}" -f "$COMPOSE_FILE" run --rm tests bats tests/merge_opensearch_yml.bats "$@"
