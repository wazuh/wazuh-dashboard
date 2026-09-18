# Prettier configuration across the Wazuh dashboard forks

This page records how Prettier is configured in the Wazuh dashboard fork
repositories, and why the configurations are deliberately not unified.

## Decision

Every fork keeps the Prettier configuration of its upstream parent, byte for
byte. A fork does not adopt another fork's style, and it does not adopt this
repository's style either.

The consequence is accepted on purpose. The same code formats differently
depending on which repository it lives in.

## Why

These repositories are forks, and we synchronize them with their upstream
parents. Changing a fork's Prettier configuration reformats the upstream files
that the fork carries, and every reformatted file then conflicts on the next
upstream merge. We pay that cost on every sync, and it lands on whoever runs the
merge rather than on whoever changed the configuration.

Style divergence between repositories costs far less. It costs one
`prettier --write` over the files being ported, once, when the port happens. A
permanently larger diff against upstream costs more than that, and it keeps
costing it.

So: do not reformat upstream files to satisfy a style preference.

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

Two deviations from upstream exist. Neither one reformats upstream files, so both
stay.

- `wazuh-dashboard-security-analytics` adds a `.prettierrc`. Its upstream parent
  has none and falls back to Prettier's defaults. Deleting the file would
  reformat the repository.
- Every fork adds `prettier` to `devDependencies`. No upstream parent declares
  it, and the forks need it for the pre-commit hook and the CI check.

## What this means when you write code

- Formatting follows the repository, not the author. The pre-commit hook runs
  `prettier --check` over the staged files, so run `prettier --write` on what you
  touched instead of formatting it by hand.
- When you port code between repositories, reformat the ported files in the same
  commit. Reviewers should expect that diff.
- Pre-existing drift is not your problem. The `5_codelinter_prettier.yml`
  workflow checks only the files a pull request changes, so files that nobody
  ever formatted fail nothing until somebody edits them. Do not reformat files
  you are not otherwise changing. That carries the same upstream conflict cost as
  changing the configuration.

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

Then add `prettier` to `devDependencies`, add the pre-commit hook and the
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
Prettier major on its own, because that reintroduces the divergence this page is
about.

## Known problem

`wazuh-security-dashboards-plugin/.prettierrc` fails `prettier --check` itself.
It uses four-space indentation and has no final newline. It comes from upstream
that way. Nothing breaks today, because the check runs only on the files a pull
request changes and no pull request changes that file. Fixing it would move the
fork away from upstream for no gain.
