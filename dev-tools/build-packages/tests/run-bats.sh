#!/usr/bin/env bash
set -euo pipefail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/tests/test.yml"

# Available services (matrix): yq v4, yq legacy, awk fallback
SERVICES=(tests-yqv4 tests-yqlegacy tests-awk)
SERVICE_LABELS=(yqv4 yqlegacy awk)

usage() {
  cat <<EOF
Usage: $0 [-s SERVICE] [--list] [--] [BATS_ARGS...]

Run Bats tests inside Docker Compose services:
  -s, --service  One of: yqv4 | yqlegacy | awk (default: run all)
      --list     List services and exit
  --             Stop parsing and pass the rest to bats

Examples:
  $0                         # run matrix (all services)
  $0 -s yqv4 -f 'deep merge' # run only yq v4 service with filter
  $0 -- -t                   # pass -t to bats
EOF
}

# Detect docker compose
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "Docker Compose is required (docker compose or docker-compose)." >&2
  exit 127
fi

# Parse args
SELECTED_SERVICES=()
BATS_ARGS=()
while (( $# )); do
  case "$1" in
    -s|--service)
      shift
      case "${1:-}" in
        yqv4) SELECTED_SERVICES+=(tests-yqv4) ;;
        yqlegacy) SELECTED_SERVICES+=(tests-yqlegacy) ;;
        awk) SELECTED_SERVICES+=(tests-awk) ;;
        *) echo "Invalid service: ${1:-}" >&2; usage; exit 2 ;;
      esac
      shift ;;
    --list)
      printf "%-14s %s\n" yqv4 tests-yqv4
      printf "%-14s %s\n" yqlegacy tests-yqlegacy
      printf "%-14s %s\n" awk tests-awk
      exit 0 ;;
    --)
      shift
      BATS_ARGS+=("$@")
      break ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      BATS_ARGS+=("$1")
      shift ;;
  esac
done

if [ ${#SELECTED_SERVICES[@]} -eq 0 ]; then
  SELECTED_SERVICES=(${SERVICES[@]})
fi

# Build only selected
"${COMPOSE[@]}" -f "$COMPOSE_FILE" build --pull "${SELECTED_SERVICES[@]}"

rc_all=0
for svc in "${SELECTED_SERVICES[@]}"; do
  echo "==> Running bats in $svc"
  set +e
  "${COMPOSE[@]}" -f "$COMPOSE_FILE" run --rm "$svc" bats tests/merge_opensearch_yml.bats "${BATS_ARGS[@]}"
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    rc_all=$rc
  fi
done

exit $rc_all
