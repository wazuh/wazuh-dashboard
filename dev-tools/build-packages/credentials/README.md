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

The dashboard owns no credential and publishes nothing. It consumes two passwords into its
keystore:

| Key                                   | Env-only alias     | Account        | Owner   | Keystore entries                                          |
| ------------------------------------- | ------------------ | -------------- | ------- | --------------------------------------------------------- |
| `WAZUH_INDEXER_KIBANASERVER_PASSWORD` | `INDEXER_PASSWORD` | `kibanaserver` | Indexer | `opensearch.username` (`kibanaserver`), `opensearch.password` |
| `WAZUH_MANAGER_WUI_PASSWORD`          | `API_PASSWORD`     | `wazuh-wui`    | Manager | `wazuh_core.hosts.default.password`                       |

For each key, the ladder is:

0. The keystore entry already exists: resolved. Nothing else is read.
1. The process environment (scoped name, then alias), then `credentials.env`: validated against
   the password policy and stored in the keystore through stdin. A value that fails the policy is
   reported as `INVALID`, naming the key and the rule, never the value.
2. Never generated: inventing a value does not make the peer accept it.
3. Absent everywhere: unresolved.

## Modes

| Mode         | Called from                              | Exit status                                    |
| ------------ | ---------------------------------------- | ---------------------------------------------- |
| `--install`  | fresh `postinst` / `%post`               | always `0`, no warning                         |
| `--upgrade`  | `postinst` / `%post` on upgrade          | always `0`, no warning                         |
| `--prestart` | `ExecStartPre=+` and the SysV init start | `1` naming every unresolved or invalid key     |
| `--clear`    | image builds only (e.g. end of a Dockerfile) | removes the three keystore entries above |

`--install` and `--upgrade` also create `/etc/wazuh` (`0700`) and an empty `credentials.env`
(`0600 root:root`) when the dashboard is the first Wazuh package on the host.

`-H <dir>` sets the installation directory (default: derived from the script's location), and
`WAZUH_SHARED_HELPER_DIR` sets where to find `wazuh-credentials.sh`. `WAZUH_BASE_DIR` moves
`/etc/wazuh`, as for every other consumer of the library.

## Building

`build-packages.sh` copies this directory into the base builder. `base-builder.sh` then installs
the script and downloads the library from
`https://raw.githubusercontent.com/wazuh/wazuh-installation-assistant/<ref>/credentials_lib/wazuh-credentials.sh`:

- `WAZUH_CREDENTIALS_LIB_REF`: the ref to download from. Defaults to the package version (the
  `5.0.0` branch for a `5.0.0` build).
- `WAZUH_CREDENTIALS_LIB_SHA256`: when set, the download must match it.

A failed download or a checksum mismatch fails the build. There is no bundled fallback.
