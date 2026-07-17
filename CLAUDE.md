# CLAUDE.md

Wazuh-owned AI context for **`wazuh-dashboard`**. Keep it short: this file points
to the source-of-truth docs instead of duplicating them. Read the linked doc
before doing non-trivial work.

## What this repo is

The **platform**: a fork of **OpenSearch Dashboards (OSD)** adapted for Wazuh. It
is _not_ the Wazuh app — the app lives in the sibling repo
`wazuh-dashboard-plugins`, whose plugins are installed into this platform's
external `./plugins/` directory.

- OSD base version: `package.json` → `version` (e.g. `3.6.0`).
- Wazuh version: `VERSION.json` and `package.json` → `wazuh` (e.g. `5.0.0`,
  revision `04`).
- Node: see [`.nvmrc`](.nvmrc) (currently 22.22.0). Package manager: Yarn v1
  (`packageManager` = `yarn@1.22.19`), Yarn **workspaces** (single dependency
  tree, unlike the plugins repo).
- Default branch `main`; work happens on version branches (`4.14.x`, `5.0.0`,
  `6.0.0`, …).

## Architecture — read this before importing anything

Four top-level code areas — the #1 source of confusion is `src/plugins/` vs
`./plugins/`:

| Path            | Role                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------- |
| `src/core/`     | The platform itself: HTTP, plugin system, saved objects, config, logging. Exposes `setup`/`start` contracts. Has `public/` + `server/`. |
| `src/plugins/`  | ~68 **built-in** OSD plugins, part of the main bundle (data, dashboard, discover, …).                    |
| `packages/`     | Internal `@osd/*` workspace packages (optimizer, dev-utils, plugin-helpers, i18n, …).                    |
| `./plugins/`    | **External plugins install target** — where `wazuh-dashboard-plugins` (and other Wazuh dashboard plugins) are placed and bootstrapped. |

**Do NOT confuse `src/plugins/` (built-in) with `./plugins/` (external Wazuh
plugins).** `packages/osd-agents/` is an unrelated experimental Bedrock agent —
**not** a Claude skill.

### `public/` vs `server/` vs `common/` (import rules — strict)

Every plugin (built-in or external) splits into layers bundled **separately**:

- **`public/`** — runs in the **browser** (React, EUI/OUI, `core.http`). Uses
  DOM/`window`.
- **`server/`** — runs in **Node.js** (Hapi routes under `/api/`, saved objects,
  services). Uses `fs`, server context, secrets.
- **`common/`** — **isomorphic** code shared by both: constants, types, pure
  helpers. No DOM, no Node-only APIs.

Rules: `public/` must **never** import from `server/` and vice-versa; both may
import from `common/`; cross-plugin access goes **layer-to-layer** and only via a
plugin's declared `setup()`/`start()` contracts + `requiredPlugins` /
`optionalPlugins` in `opensearch_dashboards.json` — never reach into internal
paths.

### Plugin lifecycle

`setup(core, deps)` (register routes, saved objects, UI apps, services) →
`start(core, deps)` (start listeners / expose runtime APIs) → `stop()` (cleanup).
Use `core.getStartServices()` in app mount handlers instead of storing `start`
references as class fields.

## Commands

Real scripts here (a single workspace, unlike the per-plugin plugins repo):

```bash
yarn osd bootstrap                              # install deps + build internal packages
yarn osd bootstrap --single-version=loose       # when mixing plugin versions
yarn start                                       # raw OSD dev server :5601 (needs OpenSearch — see "Local run model" below)
yarn start --run-examples                        # dev server with example plugins
yarn test:jest [path]                            # unit tests
yarn test:jest_integration                       # integration tests
yarn lint                                         # eslint + stylelint
node scripts/eslint --fix                         # eslint autofix
yarn typecheck                                     # node scripts/ts_error_checker.js
yarn cypress:run-without-security                  # preferred E2E
node scripts/precommit_hook.js --fix               # pre-commit (lint + typecheck)
yarn build --linux --skip-os-packages --release    # base package
```

Unlike the plugins repo, unit tests generally run **on the host** here (the full
OSD checkout ships `setup_node_env`). When modifying `src/core/public/` or
`src/core/server/` APIs, run `yarn docs:acceptApiChanges` and commit the updated
`*.api.md` files.

## Code conventions

Enforced by tooling — run the linter/formatter, don't hand-format:

- **Filenames:** `snake_case` (e.g. `index_pattern.ts`, not `IndexPattern.ts`) —
  this differs from the plugins repo's kebab-case.
- TypeScript-first; avoid `any` (prefer `unknown`/generics), `!.` and
  `@ts-ignore`. **Named exports**, no default exports.
- Single quotes; 100-char print width; ES5 trailing commas (Prettier —
  [`.prettierrc`](.prettierrc)).
- **API routes** start with `/api/`, `snake_case` paths/params/body fields.
- `id` and `data-test-subj` values are camelCase.
- SASS: import `.scss` at the top of the component; 3-letter scoping prefix on
  class names.
- React: prefer functional components; action props named `on<Subject><Change>`.
- English everywhere (code, comments, commits, docs). Full style in
  [`src/core/CONVENTIONS.md`](src/core/CONVENTIONS.md).

## Testing

- **Unit** (`*.test.ts[x]`): Jest, react-testing-library (not enzyme snapshots);
  aim for 80%+ coverage. See [`src/core/TESTING.md`](src/core/TESTING.md).
- **Integration** (`**/integration_tests/**`): `yarn test:jest_integration`.
- **Functional:** Cypress (preferred). **Do not write new Selenium/FTR tests.**
  Use `data-test-subj` selectors, `cy.intercept()` (no hard-coded delays), UTC.

## Two-repo model & build tooling

- Wazuh plugins are cloned and moved into `./plugins/` (see
  [`dev-tools/build-dev-image/install-plugins.sh`](dev-tools/build-dev-image/install-plugins.sh))
  and bootstrapped alongside the platform.
- Package assembly lives under [`dev-tools/build-packages/`](dev-tools/build-packages/)
  and [`dev-tools/build-dev-image/`](dev-tools/build-dev-image/).

## Local run model — the dev environment lives in the plugins repo

**To run/develop the whole stack locally, use the sibling `wazuh-dashboard-plugins`
repo's Docker dev env — not a `yarn start` from here.** The `yarn start` above is
the raw OSD dev server (needs you to provide OpenSearch yourself); the canonical,
supported way to bring up this platform together with the Wazuh plugins is:

```bash
cd ../wazuh-dashboard-plugins/docker/osd-dev
./dev.sh up --base [abs-path]          # runs THIS wazuh-dashboard as the platform base
                                       # (auto-detected from the sibling checkout)
# mount external plugin repos on demand (repeatable):
#   -r wazuh-dashboard-security-analytics -r wazuh-dashboard-notifications ...
# ./dev.sh --help lists every flag. OSD comes up on https://0.0.0.0:5601
```

- The dev env there starts the OSD platform + the Wazuh-owned plugins (`main`,
  `wazuh-core`, `wazuh-check-updates`) and mounts any external plugin repos passed
  with `-r`. It is a **hybrid model, not a monorepo**.
- This repo (`wazuh-dashboard`) is consumed as the `--base` platform; the other
  dashboard-plugin fork repos are mounted alongside it. None of those repos owns a
  dev environment — orchestration is centralized in `wazuh-dashboard-plugins`.
- See `../wazuh-dashboard-plugins/docker/osd-dev/README.md` for the full flag set.

## Git / PR workflow

Full detail in [`CONTRIBUTING.md`](CONTRIBUTING.md). Essentials:

- Branch names: `<type>/<issue#>-<kebab-desc>` (`fix/`, `enhancement/`, `feat/`,
  `bug/`, `change/`, `doc/`). PR base = the target **version branch**, not always
  `main` — confirm it.
- **Sign commits** (DCO `--signoff`). Imperative, capitalized subject.
- Open PRs as **Draft** (CI skips drafts); run lint + tests locally, then "Ready
  for review". Squash merge for single-purpose PRs.
- UI changes require a screenshot/video in the PR (`## Screenshot` section of the
  [PR template](.github/pull_request_template.md)).
- **Changelog:** the Wazuh user-facing changelog is [`CHANGELOG.md`](CHANGELOG.md)
  (entries **link to the issue, not the PR**). The `changelogs/fragments/*.yml`
  system and the PR's `## Changelog` section are inherited upstream OSD tooling —
  Wazuh maintains `CHANGELOG.md` by hand; use `- skip` (or a conventional
  `feat:`/`fix:` line) in the PR `## Changelog` section.
- Issues arrive as URLs and may live in another repo. Issues from
  `internal-devel-requests` are internal: don't expose their link in the PR
  ("Issues Resolved" empty) and add no CHANGELOG entry.

## Fork coexistence

The inherited upstream OSD `CLAUDE.md` described OpenSearch only. This file is
Wazuh-owned; on upstream syncs, **Wazuh content wins** and relevant upstream
technical notes are folded into the sections above.

## AI working rules

- Before proposing a PR: `yarn lint` + `yarn typecheck` + `yarn test:jest` pass
  for the touched areas.
- Never weaken auth/CSP/security; never commit secrets or credentials.
- Never force-push shared branches; never commit without DCO sign-off.
- Respect the `public`/`server`/`common` import rules above — when in doubt, put
  shared code in `common/`.

## Source-of-truth docs

- [`DEVELOPER_GUIDE.md`](DEVELOPER_GUIDE.md), [`README.md`](README.md),
  [`CONTRIBUTING.md`](CONTRIBUTING.md).
- [`src/core/CONVENTIONS.md`](src/core/CONVENTIONS.md),
  [`src/core/TESTING.md`](src/core/TESTING.md),
  [`src/core/PRINCIPLES.md`](src/core/PRINCIPLES.md).
- [`packages/osd-plugin-helpers/README.md`](packages/osd-plugin-helpers/README.md),
  [`dev-tools/build-dev-image/README.md`](dev-tools/build-dev-image/README.md).
