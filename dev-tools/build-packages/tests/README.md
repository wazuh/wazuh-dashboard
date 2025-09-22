# Wazuh Dashboard Build-Packages Tests (Containerized)

This folder contains a containerized test environment for the post‑install config merge helper used by Wazuh Dashboard packages.

## What’s Included

- `Dockerfile`: Minimal Debian image with test deps (bats, yq, jq, GNU tools).
- `test.yml`: Docker Compose file to build and run the tests.
- `merge_opensearch_yml.bats`: Bats test suite covering merge behavior.
- `run-bats.sh`: Host runner that builds the image and executes the suite in a container (no local deps required).

## Prerequisites

- Docker (Engine) installed locally.
- Docker Compose v2 (`docker compose`) or v1 (`docker-compose`).

## How To Run

From the repo root or anywhere:

```sh
dev-tools/build-packages/tests/run-bats.sh
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
- Build the test image via Dockerfile.
- Run the Bats suite inside the container using `test.yml`.

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

- The container includes `yq` and `jq`. When available, the merge script performs a deep, additive merge that inserts only missing nested keys beneath existing top‑level sections.
- If `yq` is not usable for deep merge, the script falls back to a safe, top‑level block append without overwriting existing values.

## Troubleshooting

- Compose warning about `version` is avoided by using a version‑less Compose file.
- If you use legacy Compose (`docker-compose`), the runner auto‑detects it.

## File Layout

- `dev-tools/build-packages/tests/Dockerfile`
- `dev-tools/build-packages/tests/test.yml`
- `dev-tools/build-packages/tests/merge_opensearch_yml.bats`
- `dev-tools/build-packages/tests/run-bats.sh`

