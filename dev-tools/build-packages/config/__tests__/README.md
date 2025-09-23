# Wazuh Dashboard Build-Packages Tests (Containerized)

This folder contains a containerized test environment for the post‑install config merge helper used by Wazuh Dashboard packages.

## What’s Included

- `Dockerfile.awk`: Debian image sin Python, para ejercitar el fallback awk/textual.
- `test.yml`: Docker Compose con un servicio por variante.
- `merge_opensearch_yml.bats`: Suite Bats que cubre comportamiento de merge.
- `run-bats.sh`: Runner que construye imágenes y ejecuta la suite en uno o todos los servicios.

## Prerequisites

- Docker (Engine) installed locally.
- Docker Compose v2 (`docker compose`) or v1 (`docker-compose`).

## How To Run

From the repo root or anywhere:

```sh
dev-tools/build-packages/tests/run-bats.sh          # ejecuta la suite (servicio awk)
dev-tools/build-packages/tests/run-bats.sh -s awk   # solo fallback awk/textual
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

## Notas sobre dependencias

- No se requieren herramientas externas de YAML. El script aplica un merge textual conservador: añade bloques top‑level faltantes y, si corresponde, inyecta líneas anidadas faltantes bajo bloques existentes; nunca sobreescribe.

## Troubleshooting

- Compose warning about `version` is avoided by using a version‑less Compose file.
- If you use legacy Compose (`docker-compose`), the runner auto‑detects it.

## File Layout

- `dev-tools/build-packages/tests/Dockerfile.awk`
- `dev-tools/build-packages/tests/test.yml`
- `dev-tools/build-packages/tests/merge_opensearch_yml.bats`
- `dev-tools/build-packages/tests/run-bats.sh`
