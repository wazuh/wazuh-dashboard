# Wazuh Dashboard Build-Packages Tests (Containerized)

This folder contains a containerized test environment for the post‑install config merge helper used by Wazuh Dashboard packages.

## What’s Included

- `Dockerfile.yqv4`: Debian image with Mike Farah `yq` v4+ for deep merge path.
- `Dockerfile.yqlegacy`: Debian image with Python `yq` (kislyuk) to exercise legacy path.
- `Dockerfile.awk`: Debian image without any `yq` to exercise awk-only fallback.
- `test.yml`: Docker Compose file with one service per variant.
- `merge_opensearch_yml.bats`: Bats test suite covering merge behavior.
- `run-bats.sh`: Host runner that builds the images and executes the suite in one or all services.

## Prerequisites

- Docker (Engine) installed locally.
- Docker Compose v2 (`docker compose`) or v1 (`docker-compose`).

## How To Run

From the repo root or anywhere:

```sh
dev-tools/build-packages/tests/run-bats.sh          # run matrix (all variants)
dev-tools/build-packages/tests/run-bats.sh -s yqv4  # only yq v4
dev-tools/build-packages/tests/run-bats.sh -s yqlegacy  # only legacy yq
dev-tools/build-packages/tests/run-bats.sh -s awk   # only awk fallback
```

Examples:

- Filter tests by name pattern:
  ```sh
  dev-tools/build-packages/tests/run-bats.sh -f 'nested block'
  ```
- Show test timings:
  ```sh
  dev-tools/build-packages/tests/run-bats.sh -t
  ```

The script will:
- Build the required test images.
- Run the Bats suite inside the selected service(s) using `test.yml`.

## What The Suite Verifies

- Adds only missing defaults into `/etc/wazuh-dashboard/opensearch_dashboards.yml`.
- Does not overwrite user’s existing values.
- Handles upgrade artifacts: `.rpmnew`, `.dpkg-dist`, `.dpkg-new`.
- Ignores commented keys when deciding if a setting exists.
- Supports nested blocks (e.g.,
  ```yaml
  uiSettings:
    overrides:
      "home:useNewHomePage": true
  ```
  ) appending only what’s missing.
- Idempotency: multiple runs do not duplicate keys.

## Notes on yq/jq

- With `yq v4` (Mike Farah), the script performs a deep, additive merge that inserts only missing nested keys beneath existing top‑level sections.
- With `yq legacy` (Python yq) the script uses conservative strategies (append missing top‑level blocks and additive textual injection of missing nested scalars).
- With `awk` fallback (no yq present), only missing top‑level blocks are appended; no deep merges are attempted.

## Troubleshooting

- Compose warning about `version` is avoided by using a version‑less Compose file.
- If you use legacy Compose (`docker-compose`), the runner auto‑detects it.

## File Layout

- `dev-tools/build-packages/tests/Dockerfile.yqv4`
- `dev-tools/build-packages/tests/Dockerfile.yqlegacy`
- `dev-tools/build-packages/tests/Dockerfile.awk`
- `dev-tools/build-packages/tests/test.yml`
- `dev-tools/build-packages/tests/merge_opensearch_yml.bats`
- `dev-tools/build-packages/tests/run-bats.sh`
