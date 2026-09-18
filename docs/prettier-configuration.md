# Prettier in the Wazuh dashboard forks

This page records how Prettier is configured and enforced across the Wazuh
dashboard fork repositories, and why it works the way it does.

## Decision

Two rules, and they depend on each other.

1. Every fork keeps the Prettier configuration of its upstream parent, byte for
   byte. A fork does not adopt another fork's style, and it does not adopt this
   repository's style either.
2. The check enforces only what a change touches. A file that already failed on
   the base branch is skipped, so a change never has to reformat drift it
   inherited.

## Why

Upstream does not run Prettier over its own repositories. Checked against each
repository's own `.prettierrc`, upstream fails its own configuration:

| Upstream repository                    | tracked files | files that fail |
| -------------------------------------- | ------------: | --------------: |
| `alerting-dashboards-plugin`           |           789 |              90 |
| `security-analytics-dashboards-plugin` |           530 |             444 |
| `security-dashboards-plugin`           |           403 |             100 |
| `dashboards-notifications`             |           211 |              99 |
| `dashboards-reporting`                 |           179 |              76 |

None of those repositories even declares `prettier` as a dependency. The
`.prettierrc` is there for editors and for whatever files a contributor happens
to touch. So most of the code we carry was never formatted by any Prettier
configuration, and no configuration or Prettier version makes it pass. Trying
older versions makes it worse, not better.

That is why rule 1 exists. There is nothing to align to, so changing a fork's
configuration buys nothing and costs a reformat of the upstream code it carries.

Rule 2 exists because the cost lands somewhere specific. We merge upward between
version branches on a schedule, and where the OpenSearch Dashboards base differs
between two branches we cherry-pick instead of merging. Every file we reformat
diverges from its counterpart on the other branches, so every later merge or
cherry-pick that touches it conflicts. The check was already failing on those
scheduled merge pull requests before rule 2 was added.

What rule 2 does not do is let a change be sloppy. A file the change adds has to
be formatted, and a file that was formatted cannot come out unformatted.

## How the check works

[`scripts/prettier-check-changed.sh`](../scripts/prettier-check-changed.sh) takes
a base reference and a list of files. It writes each file's base version into a
throwaway tree next to a copy of the Prettier configuration, runs
`prettier --list-different` there, and drops whatever that flags from the list it
checks against the working tree.

Two callers pass different base references:

- `.github/workflows/5_codelinter_prettier.yml` passes `origin/$GITHUB_BASE_REF`,
  so a pull request is measured against the branch it targets.
- `.lintstagedrc`, through the pre-commit hook, passes `HEAD`. Without this the
  hook blocks the commit before CI is ever reached. This repository has no
  pre-commit hook, so only the workflow applies here.

## Current configuration

Each fork's `.prettierrc` and `.prettierignore` are identical to the ones in its
upstream parent.

| Repository                           | Upstream parent                                           | `.prettierrc`                                                |
| ------------------------------------ | --------------------------------------------------------- | ------------------------------------------------------------ |
| `wazuh-dashboard`                    | `opensearch-project/OpenSearch-Dashboards`                | `singleQuote`, `trailingComma: es5`, `printWidth: 100`       |
| `wazuh-dashboard-alerting`           | `opensearch-project/alerting-dashboards-plugin`           | `singleQuote`, `trailingComma: es5`, `printWidth: 100`       |
| `wazuh-dashboard-security-analytics` | `opensearch-project/security-analytics-dashboards-plugin` | `singleQuote`, `trailingComma: es5`, `printWidth: 100`       |
| `wazuh-dashboard-notifications`      | `opensearch-project/dashboards-notifications`             | `printWidth: 80`, `bracketSpacing: true`                     |
| `wazuh-dashboard-reporting`          | `opensearch-project/dashboards-reporting`                 | `printWidth: 80`, `bracketSpacing: true`                     |
| `wazuh-security-dashboards-plugin`   | `opensearch-project/security-dashboards-plugin`           | `printWidth: 100`, `bracketSpacing: true`, four-space indent |

`bracketSpacing: true` is Prettier's default, so where it appears it comes from
upstream and changes nothing. `printWidth` is the only option that changes the
output between forks.

`wazuh-dashboard-plugins` is not a fork. It is a Wazuh-owned repository, it keeps
its own configuration, and this page does not cover it.

### Deviations kept on purpose

- `wazuh-dashboard-security-analytics` adds a `.prettierrc`. Its upstream parent
  has none and falls back to Prettier's defaults. Deleting the file would
  reformat the repository.
- Every fork adds `prettier` to `devDependencies`. No upstream parent declares
  it, and the forks need it for the pre-commit hook and the CI check.

## What this means when you write code

- Formatting follows the repository, not the author. Run `prettier --write` on
  what you touched instead of formatting it by hand.
- Do not reformat files you are not otherwise changing. That is the upstream
  conflict cost the rules above exist to avoid, and the check will not ask you
  for it.
- When you port code between repositories, reformat the ported files in the same
  commit. Reviewers should expect that diff.

## Adding a new fork

Copy the upstream repository's `.prettierrc` and `.prettierignore` unchanged. If
upstream has neither, add the `.prettierrc` this repository uses, which is the
OpenSearch Dashboards base:

```json
{
  "singleQuote": true,
  "trailingComma": "es5",
  "printWidth": 100
}
```

Then add `prettier` to `devDependencies`, copy
`scripts/prettier-check-changed.sh`, wire it into the pre-commit hook and the
`5_codelinter_prettier.yml` workflow, and pin the Prettier version in the
lockfile.

## Pin the Prettier version

Prettier's output changes between releases, so the version the lockfile resolves
is part of the configuration. Every fork declares `prettier: ^2.1.1`, and they do
not all resolve to the same version. `wazuh-dashboard` and
`wazuh-security-dashboards-plugin` lock `2.1.1`. The other forks carry no lock
entry for that range, so `yarn install` takes the newest `2.x` published at
install time.

CI can therefore start disagreeing with a developer's local checkout after an
unrelated Prettier release, in a repository nobody touched. When you add or
update a fork, check that the lockfile pins the version. Never bump one fork's
Prettier major on its own.
