---
name: wiki-promote
description: "Wiki pipeline: promote a staging page to pages/ and print the git commands to commit it."
---

# wiki-promote

Promotes a page from `staging/` to `pages/`: updates frontmatter, moves the file, appends to the log, and prints the exact git commands to run.

## Usage

```
/wiki-promote <staging-file-path>
```

`staging-file-path` is the absolute path to the file in staging/. Can also be just the filename (e.g. `2026-05-11-judge-agent-pattern.md`) — the skill finds it in staging/.

---

## Wiki paths

| Location | Path |
|---|---|
| staging/ | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/staging/` |
| pages/ | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/pages/` |
| log | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/log.md` |

---

## Step 1 — Read and validate the staging file

Read the file. Confirm it exists in staging/ and has `status: staging` in frontmatter.

If status is not `staging`, stop and report: "This file has status [X], not staging. Promotion skipped."

---

## Step 2 — Update frontmatter in-place

In the staging file, update exactly two fields:
- `status: staging` → `status: current`
- `updated: [old date]` → `updated: [today's date YYYY-MM-DD]`

Do not change any other fields. Do not reformat the frontmatter.

Write the updated file back to its current location in staging/.

---

## Step 3 — Print git commands

Print the exact commands for the user to run. Do not run them yourself.

```
Run these commands:

  cd "/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki"
  git mv staging/[filename] pages/[filename]
  git add pages/[filename]
  git commit -m "promote: [concept title]"

The post-commit hook will run patch-backlinks.py automatically.
```

Use the actual filename and concept title in the output.

---

## Step 4 — Append to log.md

Append one line to `wiki/log.md`:

```
YYYY-MM-DD HH:MM | promote | pages/[filename] | staging → current
```

---

## Step 5 — Report

```
wiki-promote ready
  File:     staging/[filename]
  Title:    [concept title]
  Status:   staging → current (frontmatter updated)

  Run the git commands above to complete the move.
  The post-commit hook patches backlinks automatically.
```

---

## Hard rules

- **Never move the file yourself** — print the git mv command; the user runs it. This ensures the post-commit hook fires.
- **Only promote files with status: staging** — refuse anything else
- **Only update status and updated date** — do not edit content during promotion
- **Always log the promotion** — even before the user runs the git commands
