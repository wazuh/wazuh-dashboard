# Wazuh Dashboard Build-Packages Tests (Containerized)

This folder contains a containerized test environment for the post‑install config merge helper used by Wazuh Dashboard packages.

## What’s Included

- `Dockerfile.awk`: Minimal Debian image with test deps (bats, jq, GNU tools).
- `test.yml`: Docker Compose file to build and run the tests.
- `merge_opensearch_yml.bats`: Bats test suite covering merge behavior.
- `run-bats.sh`: Host runner that builds the image and executes the suite in a container (no local deps required).

## Prerequisites

- Docker (Engine) installed locally.
- Docker Compose v2 (`docker compose`) or v1 (`docker-compose`).

## How To Run

From the repo root or anywhere:

```sh
./run-bats.sh          # run the suite (awk service)
./run-bats.sh -s awk   # only fallback awk/textual
```

Examples:

- Filter tests by name pattern:
  ```sh
  ./run-bats.sh -f 'nested block'
  ```
- Show test timings:
  ```sh
  ./run-bats.sh -t
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

## Notes on Dependencies

- No external YAML tools are required. The script performs a conservative textual merge: it adds missing top-level blocks and, when applicable, injects missing nested lines under existing blocks; it never overwrites existing user values.

## Troubleshooting

- Compose warning about `version` is avoided by using a version‑less Compose file.
- If you use legacy Compose (`docker-compose`), the runner auto‑detects it.

## File Layout

- `./Dockerfile.awk`
- `./test.yml`
- `./merge_opensearch_yml.bats`
- `./run-bats.sh`
