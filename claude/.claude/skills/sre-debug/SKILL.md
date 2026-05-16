# Skill: sre-debug

## Purpose

Structured debugging and integration protocol. Mirrors SRE discipline: understand system state → form hypothesis → test minimally → confirm with evidence.

## When to activate

Trigger on any of the following:
- "not working", "error", "debug", "troubleshoot", "broken", "failing"
- "integrate", "configure", "can't connect", "getting 401", "returns empty"
- Any new API or service integration
- Any data pipeline not producing expected output
- Any automation that isn't firing, or is firing incorrectly

## Protocol

### 1. Understand before acting

- Read all available docs, specs, and examples **first** — before writing a single line
- Read existing config/code before proposing changes
- Check logs before hypothesising
- If the user has provided a URL, a spec, or an example — that is the ground truth. Read it.

### 2. State your hypothesis

Before making any change, write one sentence:

> "I think **X** is wrong because **Y**."

If you cannot state a hypothesis, you don't understand enough yet. Keep reading.

### 3. Test at the boundary first

| Context | Boundary test |
|---------|--------------|
| REST API | Raw curl with exact headers/auth before any wrapper or config |
| Telegraf / agent config | Manually run `telegraf --test` or equivalent |
| HA automation | Manual trigger in developer tools before enabling |
| InfluxDB query | Run in InfluxDB Data Explorer before embedding in Grafana |
| Grafana panel | Run query in panel editor before saving dashboard |
| Template sensor | Test in HA template developer tools before deploying |

Boundary testing reveals **actual** behaviour, not assumed behaviour.

### 4. One change at a time

- Never fix two things simultaneously — you won't know which one worked
- If a change doesn't fix it, revert before trying the next hypothesis
- Each attempt is a controlled experiment

### 5. Confirm with evidence

"That should work" is not confirmation. Evidence means:

| System | Evidence |
|--------|---------|
| Data pipeline (Telegraf → InfluxDB) | Query InfluxDB and show the actual data |
| HA automation | Show `last_triggered` timestamp |
| API integration | Show the actual response body |
| HA template | Show rendered output from developer tools |
| Grafana panel | Show the panel rendering with real data |

### 6. Document findings immediately

- Update memory or project CLAUDE.md as soon as something is confirmed
- Don't wait until the end of the session — context is lost between steps
- Record: what the symptom was, what the root cause was, what fixed it

## What this skill does NOT cover

- Tactical fixes for specific services (auth formats, field names, etc.) — those belong in memory/network.md or project CLAUDE.md files
- Project-specific patterns — those belong in the project's own CLAUDE.md

## The core principle

The most expensive debugging sessions share one root cause: **acting before understanding**. Wrong auth format, wrong field names, wrong endpoint — all of these are symptoms of not reading the docs first. This protocol exists to make "read first" the default, not the exception.
