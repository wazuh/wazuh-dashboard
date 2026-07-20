---
name: resolve-cve
description: Resolve a dependency CVE in the Wazuh Dashboard platform — confirm the vulnerable package is actually present and reachable, apply the least-invasive remediation (direct bump, lockfile dedupe, or scoped resolution), verify build/tests/audit, and hand off a prepared PR. Use when the user asks to fix or resolve a CVE / dependency vulnerability, or provides a CVE id or CVE issue URL.
---

# Resolve a dependency CVE

Remediation flow for a dependency vulnerability. Pairs with **analyze-dashboard-vuln**
(triage/verdict + issue drafting) — use that first if it's not yet confirmed the
repo is affected. This skill assumes remediation is wanted.

Optional input: a `CVE-XXXX-XXXXX` id or a CVE issue URL. Without one, look up open
CVE issues and ask which to resolve.

> **repo-specific (wazuh-dashboard):** this is the **platform**, a single Yarn
> **workspace** with one root `package.json` + one root `yarn.lock` (unlike the
> plugins repo's three independent plugins). Dependencies install/build via
> **`yarn osd bootstrap`**. Forced versions live in the **root `package.json`
> `resolutions`** block. Tests generally run **on the host** here (the full OSD
> checkout ships `setup_node_env`).

## Workflow

```
- [ ] 1. Identify the CVE (package, vulnerable range, safe version, severity)
- [ ] 2. Verify presence + reachability in the workspace
- [ ] 3. Remediate with the least-invasive strategy that works
- [ ] 4. Verify (bootstrap + tests + audit; vulnerable version gone)
- [ ] 5. Write a report to tmp/ and deliver via create-pr (prepare mode)
```

### 1. Identify

Read the CVE. If given an issue URL: `gh issue view <url>`. Extract: affected
package, vulnerable version range, recommended safe version, severity, and the
GHSA if present. If you cannot confirm whether the repo is truly affected, run
**analyze-dashboard-vuln** to get the reachability verdict before changing code.

### 2. Verify presence + reachability

Check the package is really installed and why:

```bash
grep -n '"<package>"' package.json          # declared as a direct dep/resolution?
grep -n '<package>@' yarn.lock | head        # resolved versions in the workspace
yarn why <package>                           # dependency chain(s)
```

If **every** path is a `devDependency` / build-test tool (cypress, jest, webpack,
etc.) or a non-runtime transitive, the repo is effectively **not affected** —
prefer documenting that (via analyze-dashboard-vuln) over forcing a change.
Remediate when a **runtime** path pulls the vulnerable version.

### 3. Remediate (least invasive first)

Back up first: `cp package.json package.json.bak && cp yarn.lock yarn.lock.bak`.
Try strategies in order:

- **A — Direct bump.** If the package is a direct dependency in the root
  `package.json`, set it to the safe version and re-run `yarn osd bootstrap`.
- **B — Lockfile dedupe.** If it's transitive, remove its entries from `yarn.lock`
  and re-bootstrap so it regenerates to a patched version.
- **C — Parent bump.** If a peer/parent constraint pins the old version, bump the
  parent dependency, then retry B.
- **D — Scoped resolution (last resort).** Add to the root `resolutions` using the
  **narrowest** path (`"**/<parent>/<package>": "<safe>"`), never a global
  override. Document why and which chain required it.

Only change versions; never remove a required dependency; follow semver; never
leave the repo in a broken state (restore the `.bak` files on failure).

### 4. Verify

> **repo-specific (wazuh-dashboard):** re-resolve and test on the host:
>
> ```bash
> yarn osd bootstrap
> yarn test:jest            # scope to affected areas where possible
> ```
>
> Then confirm the vulnerable version is gone (`yarn why <package>` / grep the
> lockfile) and check for new advisories (`yarn audit`).

If any source code was touched, also run the **check-standards** skill. Remove the
`.bak` files once verification passes.

### 5. Report + deliver

Write a short report to `tmp/cve-<id>.md` (strategy used, dependency chain
evidence, verification results — or, on failure, strategies tried and recommended
manual steps).

> **repo-specific:** `tmp/` is git-ignored in this repo (see `.gitignore`).

Then invoke **create-pr** in its default prepare-and-hand-off mode. It applies the
shared rules automatically:

- Base = the version branch the work started from (not always `main`).
- CVE issues usually live in **`internal-devel-requests`** → leave the
  `## Description` closing reference empty and **no CHANGELOG entry**. If the
  CVE issue is public, use `Closes #<issue_number>` and add a CHANGELOG entry
  (under `Fixed`/`Changed`) linking the **issue**.
- Commits DCO-signed.

Suggested PR title: `Fix <CVE-id>: bump <package> to <safe-version>`.

## Success criteria

1. No runtime path resolves the vulnerable version anymore.
2. `yarn osd bootstrap` and `yarn test:jest` pass on the host.
3. No new advisories introduced for the resolved package.
4. Report in `tmp/`, and a prepared PR (via create-pr) following repo conventions.
