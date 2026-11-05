---
name: wiki-promote
description: "Wiki pipeline: promote staging pages to pages/ (status → current), patch backlinks and log — via the tested promote.py script."
---

# wiki-promote

Promotes pages from `staging/` to `pages/`. It sets `status: current`, stamps `updated:` with today's date, moves each file, runs the backlink patcher once, and logs one line per page with the real clock time.

**All of this is done by `scripts/promote.py`.** Do not hand-roll the steps with shell loops, `perl`/`sed`, or composed timestamps.
- On 2026-11-04 a manual batch went wrong. zsh did not word-split `$FILES`, so 19 filenames landed in one malformed log entry.
- A timestamp was also invented instead of read from the clock.
- The script validates the whole batch first and changes nothing if any file fails.

The wiki lives inside the Obsidian vault managed by Obsidian Sync. Git is not the transport layer here. Do not use `git mv` or print git commands. Obsidian Sync picks up the move.

## Usage

```
/wiki-promote <staging-file> [staging-file-2 ...]
/wiki-promote all
```

Each `staging-file` can be a bare filename (e.g. `2026-05-11-judge-agent-pattern.md`) or an absolute path in staging/.

---

## Paths

| Location | Path |
|---|---|
| Wiki root | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/` |
| Promote script | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/scripts/promote.py` |
| Link checker | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/scripts/check-links.py` |
| Backlink patcher (called by promote.py) | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/scripts/patch-backlinks.py` |

---

## Step 1 — Confirm the user approved these pages

Promote only pages the user has said they reviewed and approved. "Promote all" covers everything currently in staging/. List what that includes in the report.

## Step 2 — Dry run

```bash
python3 "/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/scripts/promote.py" --dry-run <files...>
# or, for everything in staging/:
python3 "/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/scripts/promote.py" --dry-run --all
```

The script refuses, and **changes nothing**, if any file:
- is not `status: staging`;
- has no frontmatter or no `updated:` line;
- is not in staging/;
- would overwrite a file already in pages/.

Report refusals to the user. Do not work around them.

## Step 3 — Promote

Re-run the same command without `--dry-run`. Exit codes:
- `0`: success.
- `1`: refused; nothing changed.
- `2`: pages moved, but the backlink patcher failed. Re-run `patch-backlinks.py` alone; it is idempotent.

## Step 4 — Verify links

```bash
python3 "/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/scripts/check-links.py" --only pages
```

Report any `MISSING` lines and any `WARN` contradiction flags involving the promoted pages. Missing links that existed before this promotion are pre-existing, so say so rather than fixing canonical pages unasked.

## Step 5 — Report

Paste the script's `wiki-promote done` block, then add the link-check summary.

---

## Hard rules

- **Use promote.py.** Never hand-edit status lines, loop over files in the shell, or write log lines yourself.
- **Never compose a timestamp.** The script reads the clock. If you ever log anything by hand, take the time from `date "+%Y-%m-%d %H:%M"`.
- **Never use git mv.** Do not print git commands.
- **Only promote files with status: staging.** The script enforces this.
- **Do not edit content during promotion.** The script changes only the `status:` and `updated:` lines.
- **Changes to canonical pages** (e.g., resolving a contradiction) need the user's explicit approval. Log them as `update` with a note that the user approved.
