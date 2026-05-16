---
name: wiki-ingest
description: "Wiki pipeline: ingest a source file into wiki/raw/ and propose concept pages in wiki/staging/."
---

# wiki-ingest

Takes a source file (research ensemble output, intelligence briefing, knowledge file, or any markdown with discrete concepts) and runs it through the wiki pipeline: creates a raw/ entry, extracts concepts, and writes proposed pages to staging/.

## Usage

```
/wiki-ingest <source-path>
```

`source-path` is the absolute path to the source file. If omitted, ask the user which file to ingest.

---

## Wiki paths (always use these exact paths)

| Location | Path |
|---|---|
| Wiki root | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/` |
| raw/ | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/raw/` |
| staging/ | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/staging/` |
| pages/ | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/pages/` |
| log | `/Users/awalker/Documents/CLAUDE/Agentic Vault/wiki/log.md` |

---

## Step 1 — Read and classify the source

Read the source file. Determine which source type it is:

| Type | Signals | Extraction strategy |
|---|---|---|
| **ensemble** | Path contains `research_ensemble/outputs`; file is a synthesis or track output | Look for `research_node_manifest` in track-a file first; if absent, fallback extraction from synthesis |
| **research-topic** | Path contains `agent-playbook`; file is a memo with Section 11 | Look for `research_node_manifest` in Section 11 |
| **knowledge-file** | Path contains `60_Intelligence/knowledge/` or `nates-frameworks` | Extract named frameworks/patterns as individual concepts |
| **briefing** | Path contains `60_Intelligence/briefings/` or filename matches `YYYY-MM-DD-briefing` | Extract discrete named insights with claims |
| **other** | Anything else | Fallback extraction — treat as a flat document and extract named concepts |

---

## Step 2 — Derive the raw file name and slug

Derive the raw file slug from the source:
- Use the date from the source path or filename (YYYY-MM-DD)
- Use a 2–4 word lowercase hyphenated slug from the content topic
- Full raw filename: `YYYY-MM-DD-[slug].md`

Check if a raw entry for this source already exists in `raw/`. If it does, note it and continue to concept extraction — do not recreate it.

---

## Step 3 — Create the raw/ entry

If the raw entry does not already exist, write it to `raw/YYYY-MM-DD-[slug].md` with this exact structure:

```markdown
---
wiki_raw_entry: true
date: YYYY-MM-DD
slug: [slug]
source_type: [ensemble | research-topic | knowledge-file | briefing | other]
source_path: [absolute path to the source file]
ingest_note: [1–2 sentence summary of what was extracted and confidence distribution]
---

# Source: [Human readable title] ([date])

**Research question / topic:** [the question the source answers, or the topic it covers]

**Key finding:** [the single most important claim or finding — 1–2 sentences]

**Core concepts identified:**
- C1: [concept name] — [one-line description] ([High | Medium | Low])
- C2: [concept name] — [one-line description] ([High | Medium | Low])
[... all concepts, including those below threshold with (Low — skipped)]

See full source at `source_path` above.
```

---

## Step 4 — Concept extraction rules

Extract discrete concepts from the source. A concept deserves a wiki page if it:

1. **Has a distinct name** — a named pattern, framework, principle, mechanism, or finding (not a generic statement)
2. **Stands alone** — could be understood without reading the full source document
3. **Makes a non-obvious claim** — captures something that would surprise or inform a reader who knows the domain
4. **Has a defensible argument** — not just a label; there is something to say about why it's true

**Do not extract:**
- Common knowledge or domain basics
- Tactical / temporary observations that won't matter in 6 months
- Meta-commentary about the research process itself
- Exact duplicates of concepts already in staging/ or pages/ (check by slug)

### Confidence mapping

| Label | Score | Decision |
|---|---|---|
| High | 0.85 | Create page |
| Medium | 0.65 | Create page |
| Low | 0.40 | Log as skipped — do not create page |

**Source-type specific guidance:**

**Ensemble outputs:** Named convergence findings, named divergence points, named frameworks, the integrated hypothesis. Skip: process observations, obvious methodology notes.

**Knowledge files (nates-frameworks etc.):** Each named `###` framework heading = one candidate concept. Focus on the claim the framework makes, not just its existence. Only ingest frameworks that don't already have wiki pages.

**Briefings:** Named insights with clear claims. Skip: passing mentions, speculative one-liners without supporting evidence.

---

## Step 5 — Check for existing slugs

Before creating any staging page, check that its slug does not already exist in `staging/` or `pages/`. Use `ls` on both directories and compare.

If a slug already exists:
- Log it as `ingest-skip | [slug] | already exists in [staging|pages]`
- Do not overwrite

---

## Step 6 — Write staging pages

For each concept with confidence >= 0.5, write a page to `staging/YYYY-MM-DD-[concept-slug].md`.

Use the date from the raw file (the source date, not today's date).

**Required frontmatter (exact field names, exact order):**

```yaml
---
slug: [concept-slug]
title: [Human Readable Title — lead with the claim, not the label]
status: staging
confidence: [0.85 | 0.65]
tags: [tag1, tag2, tag3]
created: YYYY-MM-DD
updated: YYYY-MM-DD
source: wiki/raw/YYYY-MM-DD-[slug].md
extends: []
contradicts: []
backlinks: []
---
```

**Title format:** Lead with the claim or mechanism, not just the label. Good: "Agent Education Stalls at Individual Capability — Nobody Teaches the System Level". Bad: "Agent Education Ceiling".

**Tags:** 3–6 tags. Use existing tags from pages/ where concepts are related (consistency helps Obsidian grouping).

**Body structure:**

```markdown
## Summary

[2–4 sentences. State the concept, why it matters, and the key implication. Write as if the reader hasn't seen the source.]

## [Section 1 — the main claim or mechanism]

[Explanation. Use sub-headers if the concept has distinct components.]

## [Section 2 — evidence or support]

[What supports this? Examples, data, analogies.]

## [Section 3 — implications / applications] (if warranted)

[What does this mean for decisions or practice?]

## Connections

- [[related-slug]] — [why connected]
- [[related-slug]] — [why connected]
```

**Connections:** Link to existing wiki pages (staging/ or pages/) where relevant. Use the slug as the link target. Do not invent links — only link if you have read a page and confirmed the connection is real.

---

## Step 7 — Append to log.md

After all files are written, append entries to `wiki/log.md`. One line per operation.

Format: `YYYY-MM-DD HH:MM | [operation] | [target] | [summary]`

Operations:
- `ingest` — raw entry created or staging page created (one line each)
- `ingest-skip` — concept skipped with reason
- `ingest-existing` — raw entry already existed, skipped creation

Use today's date and approximate current time.

Example entries:
```
2026-05-11 14:30 | ingest | raw/2026-05-11-agent-curriculum-pm.md | ensemble output; fallback extraction; 7 concepts identified
2026-05-11 14:30 | ingest | staging/2026-05-11-72-hour-transfer-window.md | created; source agent-curriculum-pm
2026-05-11 14:30 | ingest-skip | agent-curriculum-pm C4 governance-pm-boundary | confidence 0.40 Low — below threshold
```

---

## Step 8 — Report to user

After completing all writes, report:

```
wiki-ingest complete
  Raw entry:     raw/YYYY-MM-DD-[slug].md
  Staging pages: N created
    • YYYY-MM-DD-[slug].md — [concept title]
    • ...
  Skipped:       N (below threshold or already exists)
  Logged:        wiki/log.md

Run /wiki-promote staging/[filename].md on any page you want to promote to pages/.
```

---

## Hard rules

- **Never overwrite pages/** — wiki-ingest only writes to raw/ and staging/
- **Never modify existing raw/ entries** — they are immutable once written
- **Never create pages for concepts you have not read the source for** — do not invent concepts
- **Always check slug uniqueness before writing** — a staging page must not duplicate an existing staging or pages slug
- **Log every operation** — including skips; the log is the audit trail
- **backlinks field must always be a single-line inline list** — `backlinks: []` or `backlinks: ["slug1", "slug2"]` — NEVER a multi-line YAML list

---

## Checklist (verify before reporting done)

- [ ] Source file read and classified
- [ ] Raw file name derived correctly (YYYY-MM-DD-slug format)
- [ ] Raw entry written (or noted as already existing)
- [ ] All concepts identified and scored
- [ ] Slug uniqueness checked against both staging/ and pages/
- [ ] Staging pages written for all concepts with confidence >= 0.5
- [ ] All skips logged with reason
- [ ] log.md appended (one line per operation)
- [ ] User report printed
