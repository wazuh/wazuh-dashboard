---
name: issue-creation
description: Create a well-formed GitHub issue in a Wazuh Dashboard repo — pick the right issue template, run an issue-first duplicate check, and produce a ready-to-file body with the template's default labels. Use when the user asks to create, open, file, or draft an issue.
---

# Create a Wazuh Dashboard issue

Pick the right issue template, check for duplicates first, then fill the
template verbatim and hand off a ready-to-file body.

## Workflow

Copy this checklist and track progress:

```
- [ ] 1. Classify intent → choose issue template (ask only if ambiguous)
- [ ] 2. Issue-first check: search existing issues for duplicates
- [ ] 3. Fill the chosen .github/ISSUE_TEMPLATE/*.md verbatim
- [ ] 4. Keep the template's default labels; add a triage label only if named
- [ ] 5. Emit the ready-to-file body + report (default stop; gh issue create only if asked)
```

### 1. Classify intent → choose template

Map the user's intent to a template. Ask the user only when genuinely
ambiguous between two rows.

| Intent | Template | Labels (from template frontmatter) |
|--------|----------|--------|
| Defect/regression | `bug_template.md` | `bug, untriaged` |
| New capability/idea | `feature_template.md` | `enhancement` |
| Support a new OpenSearch version | `compatibility_request.md` | `compatibility, level/task, type/research` |
| Track a Wazuh release | `new_release.md` | `level/task, type/enhancement` |
| Engineering task/improvement (not a bug, feature, compatibility, or release) | `task_template.md` | `level/task, type/task` |

### 2. Issue-first duplicate check

Before drafting, search for an existing issue covering the same problem:

```bash
gh issue list --search "<keywords>"
gh search issues "<keywords>" --repo wazuh/wazuh-dashboard
```

On a likely match, surface it to the user and ask whether to proceed with a
new issue or comment on the existing one instead.

### 3. Fill the template

Reference the chosen file under
[`.github/ISSUE_TEMPLATE`](../../../.github/ISSUE_TEMPLATE) — read it first and
fill it verbatim; do not inline template bodies in this skill.

> **repo-specific (wazuh-dashboard):** templates are classic `.md` issue forms
> (not YAML issue forms). Label sets per template:
> - `bug_template.md` → `bug, untriaged`
> - `feature_template.md` → `enhancement`
> - `compatibility_request.md` → `compatibility, level/task, type/research`
> - `new_release.md` → `level/task, type/enhancement`
> - `task_template.md` → `level/task, type/task`
>
> **Label frontmatter is stale, do not repeat it verbatim without checking**
> — `feature_template.md` declares a bare `enhancement` label, but this
> repo's actual label set has no such label — only the prefixed
> `type/enhancement` (confirmed via `gh label list --repo wazuh/wazuh-dashboard`).
> GitHub only applies a template's `labels:` frontmatter if that exact label
> already exists in the repo, so filing via `feature_template.md` as-is
> silently applies no type label. `bug_template.md`'s bare `bug` label IS
> real here (unlike every sibling repo in this cross-repo initiative) — this
> repo uniquely has both `bug` and `type/bug`.

### 4. Labels

Keep the template's default labels as-is; add an extra triage label only if
the user explicitly names one. Do not invent labels or an approval workflow —
there is no `status:*` label convention in this repo.

### 5. Emit the ready-to-file body + report

**Default deliverable — stop here.** Output the filled issue body plus a short
report for the human to review:

```
Issue pre-flight
- Template: <file>
- Labels: <label list>
- Duplicate check: no matches found / possible match: <issue-url>
- Command to open it: gh issue create --template <file> --label "<labels>"
```

Only run `gh issue create` when the user explicitly asks you to open the
issue.
