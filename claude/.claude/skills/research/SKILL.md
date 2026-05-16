# Research Ensemble Skill

A multi-track research skill that produces decision-grade analysis no single pass can match.
Runs four independent tracks, maps convergence and divergence, and synthesises the results.

## Trigger

Invoked via `/research [topic]` or when the user asks for "research", "investigate",
"multiple angles", "comprehensive analysis", or "ensemble research" on a non-trivial question.

Do not run for simple factual lookups or questions with a single correct answer.
If the question cannot support multiple evidence-backed framings, say so and offer
straight research instead.

---

## Step 0 — Pre-flight checks

Before doing anything else, verify tool availability.

**WebSearch (hard requirement)**
Attempt a minimal test search. If unavailable or access denied, stop and report:
`WebSearch unavailable — cannot run research ensemble.`

**WebFetch (soft requirement)**
Attempt to fetch a known-stable URL. If unavailable, proceed in **search-only mode**:
- All sources assessed from snippets only
- Every source carries `fetch_status: skipped`
- Confidence ceiling capped at Medium regardless of other factors

If both tools are unavailable, stop immediately.

---

## Step 1 — Create output directory

Create the timestamped output directory before spawning any agents:

```
research-output/YYYY-MM-DD/[topic-slug]/
```

Where:
- `YYYY-MM-DD` is today's date
- `topic-slug` is a 2–4 word lowercase hyphenated slug from the research question

Use `mkdir -p` to create it. Record the full absolute path — all outputs go here.
Substitute this real path everywhere below before passing prompts to subagents.

---

## Step 2 — Conductor analysis (complete before writing any Track Brief)

Analyse the research question across four dimensions. Complete **all four analyses**
before writing any Track Brief. Do not interleave analysis and brief-writing.

### 2.1 — Question restatement

- Rewrite the question in precise, unambiguous terms
- Identify hidden assumptions (what the question takes for granted)
- Identify scope ambiguities and causal ambiguities
- State the question type: descriptive / causal / predictive / normative / mixed
- Write the restated question — this is Track A's research question and the anchor for all tracks

### 2.2 — Lens selection (Track B)

Select exactly three disciplinary lenses that frame the question differently.

**Structural distinctness requirement:** lenses must differ in causal model, unit of
analysis, evidence tradition, and what counts as explanation. Adjacent lenses that
merely relabel the same logic are not acceptable.

**Lens bank:**

| Cluster | Examples |
|---|---|
| Human behaviour | Evolutionary psychology, behavioural economics, sociology, anthropology |
| Systems | Complex systems, information theory, ecology, urban planning |
| History / time | Economic history, institutional history, technology history |
| Power / incentives | Political economy, game theory, organisational theory |
| Design / function | Engineering systems, architecture, human factors |
| Natural world | Biology, evolutionary biology, ecology |
| Philosophy / ethics | Ethics, epistemology, philosophy of science |

**Score each candidate lens 1–5 on:**
- Independence — how structurally different it is from the other selected lenses
- Evidence availability — whether credible source material likely exists
- Explanatory power — whether it could materially change the answer

**Reject a lens if it:** collapses into Track A logic, shares vocabulary but not mechanism
with another lens, or is too abstract to anchor evidence.

### 2.3 — Assumption inversion (Track C)

List every hidden assumption in the original question.
For each, generate an inversion or relaxation.
Select the single most productive inversion — the one that:
- Accesses a genuinely different body of evidence
- Would not be answered with the same source set as Track A
- Whose answer would materially change how the original question should be interpreted

**Inversion quality test:** if you removed the inversion and ran straight research,
would the findings differ materially? If no, the inversion is too soft — find a stronger one.

**Prefer premise-level inversions** (challenges whether the goal is right) over
answer-level inversions (explores a different path to the same goal).

### 2.4 — Analogical domain selection (Track D)

Identify 2–3 domains where the same underlying pattern or dynamic has been studied
in a different context.

**Select only if:**
- The underlying mechanism is structurally similar (not just metaphorically similar)
- The domain has a credible evidence base
- Transfer back to the original question is non-trivial but plausible

**Reject if:** the domain shares vocabulary but not mechanism, or transfer would
produce only metaphor rather than analysis.

### 2.5 — Conductor self-check

Before writing any Track Brief, confirm:

1. Do these four tracks start from genuinely different intellectual positions?
2. Are Tracks B, C, D likely to generate insights Track A would not?
3. Is the inversion sharp enough to access different literature?
4. Are the analogies structural, not decorative?
5. Are the chosen lenses evidence-bearing, not merely interesting?
6. Does Track C's inversion challenge the question's *premise* — not just its answer?

**If any answer is no, revise before proceeding.**

---

## Step 3 — Generate all four Track Briefs as a batch

Generate ALL FOUR briefs before any research begins. This is mandatory.
Generating one brief, running a track, then generating the next cross-contaminates
track independence and defeats the purpose of the ensemble.

**Track A Brief**
```
TRACK: A — Straight Research
RESEARCH QUESTION: [restated question from 2.1]
SCOPE NOTES: [key scope constraints and assumptions]
EFFORT TIER: [Light / Standard / Deep]
PERSONA_CONTEXT: [if provided, or "not specified"]
```

**Track B Brief**
```
TRACK: B — Lens Rotation
RESEARCH QUESTION: [restated question]
EFFORT TIER: [same as Track A]

LENS 1: [name]
  Causal model: [how this lens explains things]
  Key variables: [what it prioritises]
  Evidence types: [what counts as evidence]
  Expected value: [what this lens is likely to reveal]

LENS 2: [name] [same structure]
LENS 3: [name] [same structure]
```

**Track C Brief**
```
TRACK: C — Assumption Inversion
ORIGINAL QUESTION: [original, unrestated]
INVERTED QUESTION: [from 2.3]
RELEASED ASSUMPTION: [the assumption being inverted, plainly stated]
WHY THIS INVERSION: [one sentence: why it accesses different evidence]
EFFORT TIER: [same as Track A]
```

**Track D Brief**
```
TRACK: D — Analogical Bridge
ORIGINAL QUESTION: [original, unrestated]
EFFORT TIER: [same as Track A]

DOMAIN 1: [name]
  Structural similarity: [the mechanism being exploited — must be causal, not verbal]
  Domain research question: [specific question for this domain]
  Transfer mechanism: [why insights from this domain transfer back]
  Transfer risk: [what could break the analogy]

DOMAIN 2: [name] [same structure]
[DOMAIN 3 if selected]
```

---

## Step 4 — Execute all four tracks

**Fetch failure policy (pass verbatim to all subagents):**
- On WebFetch failure: retry once after 2 seconds
- On second failure: mark source `fetch_status: failed`, record URL + error, continue
- A failed fetch still occupies one source slot — no silent substitution
- If >30% of planned sources fail: add `DATA_QUALITY_WARNING` to the Confidence Summary

**Parallel mode (preferred):** spawn all four agents simultaneously via the Agent tool.
Each agent receives only its own Track Brief — no other track's brief.
Each agent must write its output immediately upon completion to the real output path:
- Track A → `[output-dir]/track-1.md`
- Track B → `[output-dir]/track-2.md`
- Track C → `[output-dir]/track-3.md`
- Track D → `[output-dir]/track-4.md`

**Important:** substitute the real output directory path (created in Step 1) into each
subagent prompt before sending. Do not pass the placeholder text.

**Sequential fallback (if Agent tool unavailable):** run A → B → C → D.
After each track completes, write its output file immediately before starting the next.

---

## Step 5 — Convergence analysis

Read all four track outputs. Map:

1. **Agreements** — where independent tracks reached the same conclusion, and why
   independent agreement matters (or note if it is superficial)
2. **Divergences** — genuine disagreements; classify as:
   factual / framing / scope / causal model / evidence asymmetry
   Do not flatten divergences — held tensions are findings
3. **Unique contributions** — what each track found that the others could not have.
   If a track produced no unique finding, say so honestly.
4. **Integrated hypothesis** — a cross-track synthesis claim not present in any single track.
   If the convergence map adds nothing beyond individual track summaries, the ensemble failed.

Write immediately to: `[output-dir]/convergence-analysis.md`

This file must be written before synthesis begins.

---

## Step 6 — Synthesis

Produce an integrated research paper grounded in the convergence analysis.

**Rules:**
1. Use the convergence map as the primary organising structure
2. Do not default to Track A as the "main answer"
3. Preserve minority but well-supported positions
4. Name unresolved tensions explicitly — do not smooth them
5. Produce at least one integrated insight not present in any individual track
6. State when the ensemble cannot resolve a dispute

Write to: `[output-dir]/synthesis-[topic-slug]-YYYY-MM-DD.md`

**Always write the synthesis file before reporting results to the user.**

---

## Step 7 — Visualisation

Produce a convergence map visualisation and save it to the output directory.

**Preferred:** run `skills/excalidraw-diagram-skill/SKILL.md` if working within the
research-ensemble project directory. Output: `[output-dir]/convergence-diagram.excalidraw`

**Acceptable alternative:** produce a self-contained HTML file with SVG layout.
Output: `[output-dir]/convergence-map.html`
Use HTML when: user requested immediate visual feedback, or Excalidraw skill is unavailable.

The visualisation must show: four tracks + central claims, agreements, divergences,
unique contributions, and the integrated synthesis hypothesis.

---

## Output structure

```
research-output/
└── YYYY-MM-DD/
    └── [topic-slug]/
        ├── track-1.md              ← Track A output (written immediately on completion)
        ├── track-2.md              ← Track B output (written immediately on completion)
        ├── track-3.md              ← Track C output (written immediately on completion)
        ├── track-4.md              ← Track D output (written immediately on completion)
        ├── convergence-analysis.md ← written before synthesis begins
        ├── synthesis-[slug]-YYYY-MM-DD.md
        └── convergence-diagram.excalidraw  or  convergence-map.html
```

---

## Effort tiers

| Tier | Use when |
|---|---|
| **Light** | Question is focused, literature is not vast, speed matters |
| **Standard** | Default. Most complex, contested, or strategic questions |
| **Deep** | Causally complex, large contested literature, high decision stakes |

When in doubt, use Standard.

---

## Checklist (verify before reporting done)

- [ ] Pre-flight passed — WebSearch confirmed available
- [ ] Output directory created before any track ran
- [ ] Conductor analysis complete before any Track Brief written
- [ ] All four track briefs generated as a batch before research began
- [ ] Each track received only its own brief — no cross-contamination
- [ ] Each track output written to disk immediately upon completion
- [ ] `convergence-analysis.md` written before synthesis began
- [ ] Synthesis written before results reported to user
- [ ] Visualisation produced and saved to output directory
- [ ] At least one cross-track agreement identified
- [ ] At least one genuine divergence held (not smoothed)
- [ ] All fetch failures recorded; DATA_QUALITY_WARNING propagated if threshold exceeded
