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
`lib/wazuh-credentials.sh` (`root:root 0644`, in a `root:root 0755` `lib/`).
It is not committed here, because a copy in this repository is a copy that can drift. The service
user cannot write it, but must be able to read `lib/`: at startup the dashboard's i18n loader lists every
top-level directory of the installation root and exits on `EACCES`.

## What the dashboard resolves

The dashboard owns no shared credential and publishes nothing into `credentials.env`. It consumes
two passwords into its keystore:

| Key                                   | Env-only alias     | Account                 | Owner   | Keystore entries                                              |
| ------------------------------------- | ------------------ | ----------------------- | ------- | ------------------------------------------------------------- |
| `WAZUH_INDEXER_KIBANASERVER_PASSWORD` | `INDEXER_PASSWORD` | `kibanaserver`          | Indexer | `opensearch.username` (`kibanaserver`), `opensearch.password` |
| `WAZUH_MANAGER_WUI_PASSWORD`          | `API_PASSWORD`     | `wazuh-internal-client` | Manager | `wazuh_core.hosts.default.password`                           |

The manager account was named `wazuh-wui` before Wazuh 5.0.0. The credentials key keeps its `WUI`
name.

The dashboard also owns two secrets of its own:

| Keystore entry                        | Used for                                                 | If it cannot be generated                                                                                       |
| ------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `wazuh_ai_assistant.encryptionKey`    | Encrypting the provider API keys the AI assistant stores | Warning only: the AI assistant is optional.                                                                     |
| `opensearch_security.cookie.password` | Sealing the session cookie                               | Warning only, and the start is not blocked, but the dashboard then keeps the built-in default until one is set. |

Each is generated (32 random bytes, base64) straight into the keystore by `--install` and
`--prestart` when neither the keystore nor `opensearch_dashboards.yml` has it, never by
`--upgrade`, and never published. An existing value is never replaced, and a restart never rotates
it. Neither is read from the environment or from `credentials.env`.

### Upgrades

`--upgrade` adds no secret the operator did not have, so a host upgraded from a version that had no
`opensearch_security.cookie.password` gets one at its first start (`--prestart`). That start ends
the sessions that were open: users log in again, once. Later starts keep the value.

### Multi-node / load balancer

Every node behind a load balancer must share the same `opensearch_security.cookie.password`. A
random value per node means a request that lands on another node cannot unseal the session cookie,
and the user is logged out. The shared value must be 32 characters or more and must not look like
JSON (a number, `true`, a quoted string...); surrounding whitespace is trimmed by the keystore. The
keystore accepts a value that breaks these rules, but the dashboard then fails its configuration
validation and does not start.

How to set it depends on when:

- **New installation.** The package has already generated a random value on each node by the time
  the install finishes, so replace it on every node, as the service user, and restart. Keep the
  shared value in a file only root can read (for example `/root/cookie-password`, mode `600`) and
  feed it on stdin, so it never appears on a command line or in the shell history:

  ```bash
  runuser -u wazuh-dashboard -- \
    /usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore add \
    opensearch_security.cookie.password --force --stdin < /root/cookie-password
  systemctl restart wazuh-dashboard
  ```

  `--force` is required: without it `add --stdin` leaves an existing entry untouched. Setting the
  value in `opensearch_dashboards.yml` does not take effect on its own, because the keystore is
  merged over the yml and the generated entry wins. If the yml is where the value should live,
  remove the entry first, as the service user (the keystore refuses to run as root), and restart:

  ```bash
  runuser -u wazuh-dashboard -- \
    /usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore remove \
    opensearch_security.cookie.password
  systemctl restart wazuh-dashboard
  ```

- **Upgrading existing nodes.** Set the shared value on every node **before** upgrading it, either
  with the same `add` command as above but without `--force` (the entry does not exist yet) or in
  `opensearch_dashboards.yml`. Generation then skips it (an entry in the keystore or the yml counts
  as already set), on every start. Without it, each node generates its own random value at its first
  start after the upgrade, and a load balancer without sticky sessions will log users out whenever
  it moves them to another node. The sessions of nodes that were running with the built-in default
  end once, when the new value takes effect; nodes that were already restarted with the shared value
  before the upgrade keep their sessions.

For each consumed key, the ladder is:

0. The keystore entry already exists, or the setting is configured in
   `opensearch_dashboards.yml`: resolved. Nothing is written, so the yml keeps authority (the
   keystore is merged over it at start). A yml `opensearch.username` is never overwritten with
   `kibanaserver`, and without a `wazuh_core.hosts.default` host the `wazuh-internal-client` entry
   is not needed. The yml is read with the dashboard's own Node and `@osd/config`; if it cannot be
   read, the check is skipped.
1. The process environment (scoped name, then alias), then `credentials.env`: stored in the
   keystore through stdin. The password policy is enforced by the owners (the indexer and the
   manager), not here. The dashboard only checks that the keystore stores the value verbatim:
   `keystore add` trims it and stores it `JSON.parse`d, so a value that is JSON (a number, `true`,
   a quoted string, an array or an object) or has surrounding whitespace is reported as
   `INVALID`, naming the key and the rule, never the value.
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
  supplies their own, e.g. from `wazuh-certs-tool`. A pair staged before install is root's (the
  service user does not exist yet), so the packages give `certs/` to `wazuh-dashboard` before the
  resolver runs: DEB with its `chown -R` of the configuration directory, RPM in `%post`.
- A partial pair (only the certificate or only the key) is refused, not completed.
- With no shared CA but dashboard material already present, no CA is minted.
- When the install mints the shared CA it records that with `.wazuh-dashboard-bootstrap-ca` in the
  CA directory. That marker is the only thing that lets `--clear` delete the CA later.
- An existing `certs/root-ca.pem` is kept, even when it is not the shared CA.
- The leaf is RSA 2048 / SHA-256, valid 3650 days, `serverAuth,clientAuth`. Its CN is
  `WAZUH_DASHBOARD_NODE_NAME` or `hostname -s`. Its SANs are `WAZUH_DASHBOARD_CERT_SANS` (an exact
  comma-separated list, `DNS:`/`IP:` or untyped; environment, then `credentials.env`) or, by
  default, the node name, the FQDN and every global-scope address. Loopback is always added.
- Files, the SAN list included, are staged in a root-only directory and published with `ln -T`,
  key first. A new `certs/` directory gets `wazuh-certs-tool`'s layout: `0500`, files `0400`,
  `wazuh-dashboard:wazuh-dashboard`.
- `--upgrade` and `--prestart` never touch the certificates. A failed issue is reported by
  `--install` itself, and exits `0`.
- Each step of the issue is printed only with `WAZUH_DASHBOARD_VERBOSE=1` (e.g.
  `sudo WAZUH_DASHBOARD_VERBOSE=1 apt install ./wazuh-dashboard.deb`). Problems always print.

## Modes

| Mode         | Called from                                  | Exit status                                                                                                                                                                                                                |
| ------------ | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--install`  | fresh `postinst` / `%post`                   | always `0`; warns only when the certificates cannot be issued                                                                                                                                                              |
| `--upgrade`  | `postinst` / `%post` on upgrade              | always `0`, no warning                                                                                                                                                                                                     |
| `--prestart` | `ExecStartPre=+` and the SysV init start     | `1` naming every unresolved or invalid key                                                                                                                                                                                 |
| `--clear`    | image builds only (e.g. end of a Dockerfile) | removes the three consumed keystore entries above, the two owned secrets (the AI assistant key and the cookie password), the certificates, and the shared CA only when this dashboard minted it (marker); must run as root |

`--install` ends with the dashboard URL (the first global address in `dashboard.pem`), the login
user (`admin`, with `WAZUH_INDEXER_ADMIN_PASSWORD` from the indexer host) and the start command.

`--install` and `--upgrade` also create `/etc/wazuh` (`0700`) and an empty `credentials.env`
(`0600 root:root`) when the dashboard is the first Wazuh package on the host.

`--clear` removes the cookie password too, so containers started from an image built with the
package do not share one session key: each one generates its own at its first start.

`--clear` enters `certs/` the way the install does and removes the files relative to it. A
`certs/` that is a symbolic link or not a directory is refused, and the clear fails.

Run as root, every mode starts the keystore and Node as `wazuh-dashboard` in a session of their
own (`setsid`), without a controlling terminal, and with an empty environment except `PATH` and
`OSD_PATH_CONF` (`env -i`).

`-H <dir>` sets the installation directory (default: derived from the script's location).
`WAZUH_BASE_DIR` moves `/etc/wazuh`, as for every other consumer of the library.

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
