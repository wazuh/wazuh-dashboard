---
name: check-standards
description: Run the same code-quality checks CI runs (Prettier format, ESLint, typecheck, and unit tests) over the current diff before pushing or marking a PR ready. Use before opening/updating a PR, when the user asks to verify standards, lint, format, or check that CI will pass.
---

# Check standards (mirror CI locally)

Runs, over the **changed files only**, the same gates CI applies on Wazuh Dashboard
PRs, so failures are caught before they burn CI minutes. Fix issues, then re-run
until clean.

The approach is generic; blocks marked **repo-specific** cover this repo's exact
commands (test runner, typecheck, lint).

## Workflow

```
- [ ] 1. Compute changed files vs the base branch
- [ ] 2. Prettier --check (autofix with --write)
- [ ] 3. ESLint (autofix with --fix)
- [ ] 4. Typecheck
- [ ] 5. Unit tests for touched code
- [ ] 6. Report pass/fail summary
```

### 1. Compute changed files

Match how CI computes them (diff against the base branch, excluding deletions):

```bash
BASE=<version-branch>            # e.g. 5.0.0 — the PR base
git fetch origin "$BASE"
CHANGED=$(git diff --name-status --diff-filter=d "origin/$BASE"...HEAD | awk '{print $NF}')
CODE=$(echo "$CHANGED" | grep -E '\.[jt]sx?$' || true)   # js/jsx/ts/tsx only
echo "$CHANGED"
```

### 2. Prettier (format)

CI runs `prettier --check --ignore-unknown` on changed files. Same locally:

```bash
npx prettier $CHANGED --check --ignore-unknown --config .prettierrc
# autofix:
npx prettier $CHANGED --write --ignore-unknown --config .prettierrc
```

### 3. ESLint

> **repo-specific (wazuh-dashboard):** a single root ESLint config
> (`.eslintrc.js`) covers the whole workspace. Run from the repo root (as CI
> does). `yarn lint` runs **ESLint + Stylelint**; for just the changed code files:
>
> ```bash
> node scripts/eslint $CODE
> # autofix:
> node scripts/eslint $CODE --fix
> ```
>
> If you touched `.scss` files, also run Stylelint (`yarn lint:style`).

### 4. Typecheck

> **repo-specific (wazuh-dashboard):** use the repo script (runs on the host —
> the full OSD checkout ships `setup_node_env`):
>
> ```bash
> yarn typecheck          # node scripts/ts_error_checker.js
> ```

### 5. Unit tests (touched code)

> **repo-specific (wazuh-dashboard):** Jest runs **on the host** here (no Docker
> container needed). Scope to the changed files for speed:
>
> ```bash
> yarn test:jest <path-or-pattern>
> # integration tests, if you touched **/integration_tests/**:
> yarn test:jest_integration <path>
> ```

Remember: unit tests are **colocated** (`*.test.ts` / `*.test.tsx` next to the
source). New source files should ship with their colocated test.

> **repo-specific (wazuh-dashboard):** if you changed a Core public/server API
> under `src/core/`, also run `yarn docs:acceptApiChanges` and commit the updated
> `*.api.md` files (CI verifies these).

### 6. Report

Summarize each gate as pass/fail; if anything failed, list the offending files and
either fix them or explain what needs manual attention:

```
Prettier:  PASS
ESLint:    FAIL (2 files) → src/plugins/foo/public/bar.tsx, src/core/server/baz.ts
Typecheck: PASS
Jest:      PASS
```

Only report "ready for review" once every applicable gate passes.
