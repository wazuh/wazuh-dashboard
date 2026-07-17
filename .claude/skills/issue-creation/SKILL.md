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
- [ ] 4. Apply the real Wazuh label for the intent (`type/bug` / `type/enhancement` / `level/task`) + `untriaged`; ignore stale frontmatter labels
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
> (not YAML issue forms). Frontmatter `labels:` per template (may be stale —
> see step 4 for the real labels to actually apply):
> - `bug_template.md` → `bug, untriaged`
> - `feature_template.md` → `enhancement`
> - `compatibility_request.md` → `compatibility, level/task, type/research`
> - `new_release.md` → `level/task, type/enhancement`
> - `task_template.md` → `level/task, type/task`
>
> `feature_template.md`'s bare `enhancement` and `compatibility_request.md`'s
> bare `compatibility` do **not** exist as real labels in this repo (confirmed
> via `gh label list --repo wazuh/wazuh-dashboard`) — only the prefixed
> `type/enhancement` does. `bug_template.md`'s bare `bug` label IS real here
> (unlike every sibling repo in this cross-repo initiative) — this repo
> uniquely has both `bug` and `type/bug`.

### 4. Labels

Several issue templates in this repo were inherited from the upstream
OpenSearch Dashboards fork and still declare stale labels in their
frontmatter (bare `enhancement`, `compatibility`) that don't exist as real
labels here — GitHub silently drops any label that doesn't exist instead of
erroring, so filing the template as-is can result in no type label at all.
Standardize on the real Wazuh label set instead of trusting the frontmatter
verbatim:

| Intent | Real label to apply |
|--------|--------|
| Bug / defect | `type/bug` (this repo's bare `bug` label is also real, but prefer `type/bug` for consistency with the rest of the label set) |
| Feature / enhancement | `type/enhancement` |
| Engineering task / chore | `level/task` |
| Every issue | `untriaged` — applied automatically on open/reopen/transfer by `.github/workflows/add-untriaged.yml`, no manual action needed |

Do not invent labels beyond this set, and do not invent an approval
workflow — there is no `status:*` label convention in this repo.

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
