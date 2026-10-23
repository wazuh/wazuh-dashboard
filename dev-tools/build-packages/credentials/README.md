# Dashboard credential resolution

`resolve-credentials.js` resolves the dashboard's passwords and TLS material at install and
start time ([#1665](https://github.com/wazuh/wazuh-dashboard/issues/1665)). It runs on the Node
runtime the package bundles, through a short launcher:

| Installed as                                            | Mode             | Source                   |
| ------------------------------------------------------- | ---------------- | ------------------------ |
| `/usr/share/wazuh-dashboard/bin/resolve-credentials`    | `root:root 0750` | `resolve-credentials`    |
| `/usr/share/wazuh-dashboard/bin/resolve-credentials.js` | `root:root 0644` | `resolve-credentials.js` |

The launcher fixes `PATH`, drops `LD_PRELOAD`, `LD_LIBRARY_PATH`, `NODE_OPTIONS` and `NODE_PATH`,
and runs the program with `node/bin/node`. Certificates are issued with `node-forge` and parsed
with Node's `crypto`; `opensearch_dashboards.yml` is read with `js-yaml`. Both are declared in
the root `package.json`. From the host it uses only `getent` (glibc), `systemctl`, and `restorecon` when
present.

## Per-package model

Each Wazuh package owns one configuration directory and publishes what its peers need in its own
`export/`. `/etc/wazuh` is never created or read.

```
/etc/wazuh-dashboard
  opensearch_dashboards.keystore   root:wazuh-dashboard 0640
  local.env                        root:root 0600, optional, the operator's
  ca/                              root:root 0700, the dashboard CA
    root-ca.pem, root-ca.key
    .wazuh-dashboard-bootstrap-ca  marker: this install minted the CA
  export/                          root:root 0700
    ca.pem                         the dashboard CA certificate
  certs/                           root:wazuh-dashboard 0750
    dashboard.pem, dashboard-key.pem
    indexer-ca.pem                 verifies the indexer (opensearch.ssl.certificateAuthorities)
    manager-ca.pem                 verifies the Server API (wazuh_core.hosts.default.ca)
    .indexer-ca.imported, .manager-ca.imported   markers: the package imported the file
```

Each connection is verified with its own peer's CA; there is no merged bundle.

## Values

| Key                                   | Env-only alias     | Publisher                                   | Keystore entries                                              |
| ------------------------------------- | ------------------ | ------------------------------------------- | ------------------------------------------------------------- |
| `WAZUH_INDEXER_KIBANASERVER_PASSWORD` | `INDEXER_PASSWORD` | `/etc/wazuh-indexer/export/credentials.env` | `opensearch.username` (`kibanaserver`), `opensearch.password` |
| `WAZUH_MANAGER_WUI_PASSWORD`          | `API_PASSWORD`     | `/etc/wazuh-manager/export/credentials.env` | `wazuh_core.hosts.default.password`                           |
| `WAZUH_DASHBOARD_CERT_SANS`           |                    |                                             | (certificate SANs, `DNS:x,IP:y,...`)                          |

The first hit wins: the process environment (scoped name, then alias), then
`/etc/wazuh-dashboard/local.env`, then the publisher's `export/credentials.env`. An empty value is
no hit.

- A password already in the keystore or set in `opensearch_dashboards.yml` is never overwritten.
  An operator's `opensearch.username` is never replaced with `kibanaserver`. Without a
  `wazuh_core.hosts.default` host, the manager password is not needed.
- `keystore add` trims the value and stores it `JSON.parse`d, so a value that is JSON or has
  surrounding whitespace is reported as `INVALID`, naming the key, never the value.
- The secrets the dashboard owns are generated, never looked up: see [Owned secrets](#owned-secrets).

The keystore CLI runs as root with `--allow-root`, an empty environment (`OSD_PATH_CONF` only),
from `/`. The keystore is set to `root:wazuh-dashboard 0640` after every operation.

## Owned secrets

| Keystore entry                        | Used for                                                 | If it cannot be generated                                                    |
| ------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `wazuh_ai_assistant.encryptionKey`    | Encrypting the provider API keys the AI assistant stores | Warning only: the AI assistant is optional.                                  |
| `opensearch_security.cookie.password` | Sealing the session cookie                               | Warning only: the dashboard starts on the built-in default until one is set. |

Each is generated (32 random bytes, base64) straight into the keystore by `--install` and
`--prestart` when neither the keystore nor `opensearch_dashboards.yml` has it, never by
`--upgrade`. An existing value is never replaced, so a restart never rotates it. Neither is read
from the environment or an env file, published, or printed.

`--clear` removes them when the resolver generated them, so containers started from an image built
with the package do not share one session key: each one generates its own at its first start.

### Upgrades

`--upgrade` adds no secret the operator did not have, so a host upgraded from a version that had no
`opensearch_security.cookie.password` gets one at its first start (`--prestart`). That start ends
the sessions that were open: users log in again, once. Later starts keep the value.

### Multi-node / load balancer

Every node behind a load balancer must share the same `opensearch_security.cookie.password`. A
random value per node means a request that lands on another node cannot unseal the session cookie,
and the user is logged out. The shared value must be 32 characters or more and must not be JSON (a
number, `true`, a quoted string...); surrounding whitespace is trimmed by the keystore. The
keystore accepts a value that breaks these rules, but the dashboard then fails its configuration
validation and does not start.

Keep the shared value in a file only root can read (for example `/root/cookie-password`, mode
`600`) and feed it on stdin, so it never appears on a command line or in the shell history. The
keystore CLI runs as root with `--allow-root`; it leaves the keystore `0600`, and the restart's
pre-start sets it back to `root:wazuh-dashboard 0640`.

- **New installation.** The package has already generated a random value on each node by the time
  the install finishes, so replace it on every node and restart:

  ```bash
  /usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore add \
    opensearch_security.cookie.password --force --stdin --allow-root < /root/cookie-password
  systemctl restart wazuh-dashboard
  ```

  `--force` is required: without it `add --stdin` leaves an existing entry untouched. Setting the
  value in `opensearch_dashboards.yml` does not take effect on its own, because the keystore is
  merged over the yml and the generated entry wins. If the yml is where the value should live,
  remove the entry first, and restart:

  ```bash
  /usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore remove \
    opensearch_security.cookie.password --allow-root
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

## Trust rules

Every file read as root must be a regular file (no symlink) in a regular directory, both owned by
root and neither group- nor world-writable. Anything else is reported as `UNSAFE <path>: <reason>`
and is never used, repaired or followed. Files are opened with `O_NOFOLLOW` and checked through
the descriptor. `--prestart` runs the same checks over `certs/`, `ca/` and `export/` at every
start, whether or not anything is left to resolve.

Writes go to a temporary file followed by a rename, through a descriptor on the target directory
opened with `O_DIRECTORY|O_NOFOLLOW` and checked with `fstat`. Node has no `renameat`, so the names
are resolved through `/proc/self/fd/<fd>/`. A new directory is created with `mkdir`, and its owner
and mode are set through a descriptor, never by path.

## Certificates

Issued by `--install` only:

- `certs/dashboard.pem` and `dashboard-key.pem` present: left alone. Only one of them: error.
- Both absent: the CA in `ca/` is used, or minted when `ca/` has none
  (`CN=wazuh-dashboard-<host>, OU=Wazuh, O=Wazuh, L=California, C=US`, 10 years, marker dropped).
  A pair staged in `ca/` by the operator (no marker) is validated and used, and never removed.
  The leaf is RSA 2048, SHA-256, 10 years backdated one day, `serverAuth,clientAuth`,
  `CN=<host>`. `dashboard.pem` holds the leaf followed by the CA. Its SANs are `DNS:<host>`, the
  FQDN when it differs, every global address of the default-route interfaces, or
  `WAZUH_DASHBOARD_CERT_SANS` (an empty list is refused); `localhost`, `127.0.0.1` and `::1` are
  always added. The CA certificate is published as `export/ca.pem`.

## Peer CAs

`--install` and `--prestart` keep one file per peer, `certs/indexer-ca.pem` and
`certs/manager-ca.pem`:

1. **Staged:** present without its `.<peer>-ca.imported` marker. The operator's (another host, an
   external PKI): used as is, never replaced, never cleared.
2. **Imported:** absent, or present with the marker. Copied from the peer's `export/ca.pem`
   whenever it differs, so a reinstalled peer is picked up at the next start.
3. Either way it must be a CA certificate, otherwise `--prestart` reports `INVALID <path>`.

A missing `indexer-ca.pem` stops the start. A missing `manager-ca.pem` is a warning: the dashboard
starts, and the Server API connection is refused until the manager is installed and the
dashboard restarted.

## Modes

`bin/resolve-credentials --install|--upgrade|--prestart|--clear [-H <config-dir>]`, as root.
`WAZUH_DASHBOARD_VERBOSE=1` prints detail lines.

| Mode         | Called from                                  | Does                                                                                                                    | Exit status                                                                                                  |
| ------------ | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `--install`  | fresh `postinst` / `%post`                   | everything; ends with the dashboard URL and login hint                                                                  | always `0`                                                                                                   |
| `--upgrade`  | `postinst` / `%post` on upgrade              | keystore and passwords only                                                                                             | always `0`                                                                                                   |
| `--prestart` | `ExecStartPre=+` and the SysV init start     | file checks, passwords, owned secrets, peer CAs                                                                         | `1` with one `MISSING`, `INVALID` or `UNSAFE` line per problem: a password, `indexer-ca.pem` or the TLS pair |
| `--clear`    | image builds only (e.g. end of a Dockerfile) | removes the keystore entries above, the pair, the imported peer CAs, the minted CA (staged ones are kept) and `export/` | `1` when the dashboard is running or something could not be removed                                          |

## Tests

```bash
node --test dev-tools/build-packages/credentials/resolve-credentials.test.js
```
