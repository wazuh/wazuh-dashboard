# Wazuh Dashboard Build-Packages Tests (Containerized)

This folder contains a containerized test environment for the post‑install config merge helper used by Wazuh Dashboard packages.

## What’s Included

- `Dockerfile.awk`: Minimal Debian image with test deps (bats, GNU tools).
- `test.yml`: Docker Compose file to build and run the tests.
- `merge_config.bats`: Bats test suite covering merge behavior.
- `run-bats.sh`: Host runner that builds the image and executes the suite in a container (no local deps required).
- `fixtures/`: Self-contained scenarios used by the Bats suite. Each scenario is a single YAML file named after the test (e.g., `rpmnew_append_missing.yml`) with four top-level keys:
  - `metadata`: Optional map with knobs for the run. Known fields are `DEFAULT_SUFFIX` (packaged suffix to create, e.g., `rpmnew`), `RUN_TWICE` (run merge twice to prove idempotency when set to `1`), `EXPECT_STATUS` (expected exit code, default `0`), `EXPECT_PACKAGED_REMOVED` (`1` if the packaged file must be deleted, `0` if it should remain), `EXPECT_DESTINATION_PRESENT` (`1` when the final config must exist, `0` when it must not), and `EXPECT_MODE` (permission expected on the final config, e.g., `640`).
  - `defined_by_user`: Snapshot of the existing config (`~` when the file should be absent).
  - `defaults`: Packaged defaults dropped next to the config (`~` when no packaged file is present, empty string for an empty file).
  - `expected`: Snapshot of the merged result (`~` when the destination should not exist).

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
- Lists merge:
  - Flow-style arrays (`key: [a, b]`) and block lists (`key:` with `- item`) are merged by appending only missing values, preserving the destination order.
  - If styles differ between destination and new defaults, the destination style is preserved (flow stays flow; block stays block).

## Notes on Dependencies

- No external YAML tools are required. The script performs a conservative textual merge: it adds missing top-level blocks and, when applicable, injects missing nested lines under existing blocks; it never overwrites existing user values.

## Troubleshooting

- Compose warning about `version` is avoided by using a version‑less Compose file.
- If you use legacy Compose (`docker-compose`), the runner auto‑detects it.

## File Layout

- `./Dockerfile.awk`
- `./test.yml`
- `./merge_config.bats`
- `./run-bats.sh`
