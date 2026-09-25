# Dashboard credential resolution

`resolve-credentials.sh` is the dashboard's half of the install-time credential resolution
ladder ([wazuh-indexer#1928](https://github.com/wazuh/wazuh-indexer/issues/1928),
[#1594](https://github.com/wazuh/wazuh-dashboard/issues/1594)). It is installed as
`/usr/share/wazuh-dashboard/bin/resolve-credentials`, `root:root 0750`.

**Only one of the two halves lives here.** `wazuh-credentials.sh`, the shared half (credentials
file format, locking, path validation, password policy), is shared with the indexer and the
manager: all three resolve against the same `/etc/wazuh/credentials.env`, so all three must agree
on it exactly. It is owned by
[wazuh-installation-assistant](https://github.com/wazuh/wazuh-installation-assistant) under
`credentials_lib/`, and `base/base-builder.sh` downloads it at package build time into
`lib/wazuh-credentials.sh` (`root:root 0640`). It is not committed here, because a copy in this
repository is a copy that can drift.

## What the dashboard resolves

The dashboard owns no shared credential and publishes nothing into `credentials.env`. It consumes
two passwords into its keystore:

| Key                                   | Env-only alias     | Account        | Owner   | Keystore entries                                              |
| ------------------------------------- | ------------------ | -------------- | ------- | ------------------------------------------------------------- |
| `WAZUH_INDEXER_KIBANASERVER_PASSWORD` | `INDEXER_PASSWORD` | `kibanaserver` | Indexer | `opensearch.username` (`kibanaserver`), `opensearch.password` |
| `WAZUH_MANAGER_WUI_PASSWORD`          | `API_PASSWORD`     | `wazuh-wui`    | Manager | `wazuh_core.hosts.default.password`                           |

The dashboard also owns one secret of its own, `wazuh_ai_assistant.encryptionKey`, which the AI
assistant encrypts the provider API keys it stores with. It is generated (32 random bytes, base64)
straight into the keystore by `--install` and `--prestart` when neither the keystore nor
`opensearch_dashboards.yml` has it, never by `--upgrade`, and never published. An existing key is
never replaced. Failing to generate it is a warning only: the AI assistant is optional.

For each consumed key, the ladder is:

0. The keystore entry already exists, or the setting is configured in
   `opensearch_dashboards.yml`: resolved. Nothing is written, so the yml keeps authority (the
   keystore is merged over it at start). A yml `opensearch.username` is never overwritten with
   `kibanaserver`, and without a `wazuh_core.hosts.default` host the `wazuh-wui` entry is not
   needed. The yml is read with the dashboard's own Node and `@osd/config`; if it cannot be read,
   the check is skipped.
1. The process environment (scoped name, then alias), then `credentials.env`: validated against
   the password policy and stored in the keystore through stdin. A value that fails the policy is
   reported as `INVALID`, naming the key and the rule, never the value.
2. Never generated: inventing a value does not make the peer accept it.
3. Absent everywhere: unresolved.

## Certificates

`opensearch_dashboards.yml` serves HTTPS from `/etc/wazuh-dashboard/certs/dashboard.pem` and
`dashboard-key.pem`, and trusts the indexer through `certs/root-ca.pem`. A fresh install
(`--install` only) issues whatever of that is missing from the **shared CA**, the one the manager
and the indexer use (`/etc/wazuh/ca`, or `WAZUH_CA_DIR`), through the shared library's
`_wazuh_ca_ensure_locked`, under its lock:

| Shared CA                       | Result                                                                                                                     |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Absent                          | A CA is minted there (`root-ca.pem` + `root-ca.key`), and the pair is issued from it. Components installed later reuse it. |
| Anchor and key present          | Reused: the pair is issued from it.                                                                                        |
| Anchor only (managed elsewhere) | `root-ca.pem` is installed, but no pair can be issued: stage one.                                                          |

- An existing complete pair is kept as it is (checked, never replaced). This is how an operator
  supplies their own, e.g. from `wazuh-certs-tool`.
- A partial pair (only the certificate or only the key) is refused, not completed.
- With no shared CA but dashboard material already present, no CA is minted.
- An existing `certs/root-ca.pem` is kept, even when it is not the shared CA.
- The leaf is RSA 2048 / SHA-256, valid 3650 days, `serverAuth,clientAuth`. Its CN is
  `WAZUH_DASHBOARD_NODE_NAME` or `hostname -s`. Its SANs are `WAZUH_DASHBOARD_CERT_SANS` (an exact
  comma-separated list, `DNS:`/`IP:` or untyped; environment, then `credentials.env`) or, by
  default, the node name, the FQDN and every global-scope address. Loopback is always added.
- Files are staged in a root-only directory and published with `ln -T`, key first. A new `certs/`
  directory gets `wazuh-certs-tool`'s layout: `0500`, files `0400`, `wazuh-dashboard:wazuh-dashboard`.
- `--upgrade` and `--prestart` never touch the certificates. A failed issue is reported by
  `--install` itself, and exits `0`.

## Modes

| Mode         | Called from                                  | Exit status                                                                                                    |
| ------------ | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `--install`  | fresh `postinst` / `%post`                   | always `0`; warns only when the certificates cannot be issued                                                  |
| `--upgrade`  | `postinst` / `%post` on upgrade              | always `0`, no warning                                                                                         |
| `--prestart` | `ExecStartPre=+` and the SysV init start     | `1` naming every unresolved or invalid key                                                                     |
| `--clear`    | image builds only (e.g. end of a Dockerfile) | removes the three keystore entries above, the AI assistant key, the certificates, and a shared CA with its key |

`--install` and `--upgrade` also create `/etc/wazuh` (`0700`) and an empty `credentials.env`
(`0600 root:root`) when the dashboard is the first Wazuh package on the host.

`-H <dir>` sets the installation directory (default: derived from the script's location), and
`WAZUH_SHARED_HELPER_DIR` sets where to find `wazuh-credentials.sh`. `WAZUH_BASE_DIR` moves
`/etc/wazuh`, as for every other consumer of the library.

## Building

`build-packages.sh` copies this directory into the base builder. `base-builder.sh` then installs
the script and downloads the library from
`https://raw.githubusercontent.com/wazuh/wazuh-installation-assistant/<ref>/credentials_lib/wazuh-credentials.sh`.

The ref is chosen the way the manager's `make deps` chooses it. The Wazuh repositories cut the
same tag names, so a tag build downloads the library from the matching tag. `build-packages.sh`
computes an ordered list, and the first ref that exists wins:

1. `WAZUH_CREDENTIALS_LIB_REF`, when set: an explicit override.
2. The tag being built (`GITHUB_REF_NAME` when `GITHUB_REF_TYPE=tag`, else
   `git describe --tags --exact-match`). A tag build tries **only** this, after the override: a
   release never falls back to a branch that keeps moving, so a tag missing upstream fails the
   build.
3. The branch being built. This only exists upstream when the branch was created there too; a
   feature branch 404s and falls through.
4. The version branch (`5.0.0`), then the version tag (`v5.0.0`).

- `WAZUH_CREDENTIALS_LIB_SHA256`: when set, the download must match it.

A failed download or a checksum mismatch fails the build. There is no bundled fallback.
