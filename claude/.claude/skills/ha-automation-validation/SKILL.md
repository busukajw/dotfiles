---
name: ha-automation-validation
description: >
  Mandatory pre-commit validation for any Home Assistant automation change.
  Triggers include: "validate automation", "pre-commit check", "before I commit",
  "check this automation", or any request to review, create, or modify a Home
  Assistant automation, script, or helper. Run proactively before calling
  ha_config_set_automation or ha_config_set_helper on any non-trivial change.
  Also invoke when adding a new entity reference, changing a sensor threshold,
  modifying Layer 1 sensor fusion logic, or touching bedtime/sleep automations.
---

# HA Automation Pre-Commit Validation

Run this procedure before every automation change. Output the checklist at the end.
A single unchecked item is a blocker — resolve it before committing.

---

## Step 1 — Entity existence check

For every `entity_id` referenced in the automation (triggers, conditions, actions,
templates), call `ha_get_state` and verify:

- State is not `unknown` or `unavailable`
- `last_updated` is recent (within the last hour for sensors that report regularly;
  within the last day for presence/contact sensors)
- The entity domain matches its intended use (e.g., `input_select` for state machines,
  `binary_sensor` for Layer 1 fused presence, `sensor` for numeric readings)

**Common failure modes:**
- Typo in entity ID (HA silently ignores triggers on non-existent entities)
- Entity was renamed — old ID still appears to "work" until the domain is reloaded
- `unavailable` sensor used as a trigger — automation will never fire

**Do not proceed if any entity is `unknown` or `unavailable`.** Diagnose first.

### 1b. Device control semantics (lock, cover, climate, select, etc.)

For any automation action that controls a device — `lock.lock`, `lock.unlock`,
`cover.open`, `climate.set_hvac_mode`, `select.select_option`, etc. — verify the
meaning of each state *from live data*, not from the entity name.

Entity names are often ambiguous. `locked_in` could mean "in-direction is locked"
(entry blocked) or "cats locked inside" (exit blocked). Reading the name alone leads
to wrong automations.

**Required steps:**
1. Call `ha_get_state` on the action target
2. Read the current state AND all attributes
3. Cross-reference with known physical reality (e.g. if a cat is currently outside,
   and the flap is `locked`, which lock entity is responsible for blocking entry?)
4. State the inferred semantic explicitly before writing the action:
   *"`lock.front_door_locked_in: locked` = cats cannot exit"*

**Applies to:** any `lock.*`, `cover.*`, `climate.*`, `select.*`, `input_select.*`
target in the action block. Skip only for entities whose states are unambiguous
by convention (`light.turn_on`, `switch.turn_off`, `media_player.play_media`).

---

## Step 2 — 4-layer architecture cross-reference

Read `presence-lighting/CLAUDE.md` and the relevant room file in `rooms/{room}.md`
before making any change to a presence-lighting automation.

Check each of the following:

### 2a. Layer boundary integrity

Automations must only read from the layer immediately below:
- Layer 2 triggers on `binary_sensor.{room}_presence` — never on raw device sensors
- Layer 3 triggers on `input_select.{room}_occupancy_state` — never on presence directly
- Layer 4 triggers on `input_select.{room}_lighting_mode` — never on occupancy state

If the automation reads across two layers (e.g. Layer 3 also triggers on a raw sensor),
flag it as an architecture violation and propose a clean fix before proceeding.

### 2b. Humidity sensor assignment

The en-suite and main bathroom each use **different** humidity sources. Using the wrong one
is a critical calibration error — the two devices have completely different response curves
for identical shower conditions.

| Room | Correct humidity entity | Do NOT use |
|------|------------------------|------------|
| Master bathroom (en-suite) | `sensor.aarons_en_suite_temp_humidity` | FP300 built-in (`sensor.master_bathroom_fp300_humidity` or similar) |
| Main bathroom | `sensor.main_bathroom_p300_humidity` (FP300 built-in, threshold-and-interval reporting mode confirmed active) | Any other humidity sensor |

**Rule:** If the automation references any humidity sensor, verify it is the correct
dedicated sensor for that room. Never swap these — thresholds are calibrated per-sensor
and are not interchangeable.

### 2c. FP300 device configuration — never touch reporting intervals

The FP300 `absence_delay_timer` (`number.{room}_fp300_absence_delay_timer` or
`number.{room}_p300_absence_delay_timer`) may be adjusted as needed.

**Do NOT reconfigure:**
- FP300 built-in humidity reporting interval (set to threshold-and-interval mode; changing
  this will break the main bathroom shower gate which relies on sub-hourly updates)
- FP300 radar sensitivity gates (g0–g5 thresholds) without a full InfluxDB calibration
  session — these are tuned values, not defaults
- Any FP300 zone boundary setting without physical presence in the room to validate

If a task requires changing FP300 configuration, stop and ask — it is almost never the
right fix.

### 2d. Lux gate completeness

Any presence-triggered light must have a lux gate unless the room is documented as an
exception in its room file. Verify:

- Layer 3 has both `occupied + lux ≥ threshold → off` AND `occupied → normal/bright`
- Cooldown lux gate mirrors the occupied gate: `cooldown + lux ≥ threshold → off` must
  appear BEFORE the unconditional `cooldown → dim`
- Lux threshold is present in the room file's calibration block (sensor entity, dry
  baseline, device-on reading, threshold value, date verified)

---

## Step 3 — Bed sensor side assignment

**Never rely on stale session memory for left/right bed side assignments.**

Before any automation that references `binary_sensor.bed_presence_ac5280_bed_occupied_left`
or `binary_sensor.bed_presence_ac5280_bed_occupied_right`, read the canonical source:

```
memory/isabellas_bedroom.md  ← if relevant to Isabella's room
```

Or verify from the project memory directly:

```
binary_sensor.bed_presence_ac5280_bed_occupied_right = Aaron's side (trigger side)
binary_sensor.bed_presence_ac5280_bed_occupied_left  = partner/son's side
```

**Cross-check:** Call `ha_get_state` on both entities and confirm both are reporting
recent updates (within 12 hours). If either is `unavailable`, the bed sensor has
likely lost its Zigbee connection — do not proceed with bedtime automation changes
until the sensor is back online.

**Bedtime trigger:** ADR 010 mandates right-side (Aaron's) only as the trigger.
Any change to the bedtime trigger must either maintain right-side-only triggering
or supersede ADR 010 with a new decision record.

---

## Step 4 — InfluxDB logging check

If the automation creates, modifies, or references any helper entity that should be
logged to InfluxDB (occupancy state machines, lighting modes, sleep mode, etc.):

### 4a. Bucket and org

- Bucket: `home_assistant`
- Org: `homeautomation`

Any InfluxDB query or write that uses a different bucket name will silently return
no data. Verify these values before writing any Flux query.

### 4b. Helper domain logging quirk (CRITICAL)

`input_select` and `input_boolean` entities will NOT be logged by InfluxDB if listed
under `include: entities:` alone. They MUST also appear in `include: domains:`.

**Correct configuration.yaml pattern:**
```yaml
influxdb:
  include:
    domains:
      - input_select
      - input_boolean
    entities:
      - input_select.open_plan_occupancy_state
      - input_select.open_plan_lighting_mode
      # ... etc
```

If a new `input_select` or `input_boolean` helper is created as part of this automation,
verify that its domain is included in the InfluxDB `domains:` block. If it is not,
it will never write data and any historical analysis will be blind to it.

### 4c. Query field name

HA InfluxDB schema stores string states (occupancy_state values, lighting mode values)
in the `state` field, not `_value`. Flux queries must use:

```flux
filter(fn: (r) => r["_field"] == "state")
```

InfluxQL queries must use:
```sql
SELECT "state" FROM "units" WHERE "entity_id" = 'entity_slug'
```

Note: entity slugs in InfluxDB do NOT include the domain prefix (e.g. stored as
`open_plan_occupancy_state`, not `input_select.open_plan_occupancy_state`).

---

## Step 5 — Output validation report

After running Steps 1–4, output the following checklist. Every item must be checked
before the automation change is committed via `ha_config_set_automation`.

```markdown
## HA Automation Validation Report — {automation_name}

### Step 1: Entity existence
- [ ] All entity_ids verified via ha_get_state
- [ ] No entity is `unknown` or `unavailable`
- [ ] last_updated timestamps are current for all sensors
- [ ] Entity domains match intended use

### Step 2: 4-layer architecture
- [ ] Layer boundaries respected (no cross-layer reads)
- [ ] Humidity sensor is the correct dedicated sensor for this room
- [ ] No FP300 reporting interval or zone config changes
- [ ] Lux gate present and calibrated (or exemption documented in room file)
- [ ] Cooldown lux gate mirrors occupied lux gate

### Step 3: Bed sensor assignment
- [ ] N/A — automation does not reference bed sensors
      OR
- [ ] Side assignment verified against canonical source (right = Aaron)
- [ ] Both bed sensors reporting recent state via ha_get_state
- [ ] ADR 010 maintained (right-side-only trigger) or explicitly superseded

### Step 4: InfluxDB logging
- [ ] N/A — no new helpers created, no InfluxDB references
      OR
- [ ] Bucket = `home_assistant`, org = `homeautomation`
- [ ] New input_select/input_boolean helpers added to `domains:` block
- [ ] Flux/InfluxQL queries use `_field == "state"` and slug-only entity IDs

### Decision
- [ ] All items checked — ready to commit
      OR
- [ ] Blocked: {describe the issue}
```

---

## Relationship to Other Skills

- **`ha-sensor-threshold-debug`** — use this skill when a numeric threshold is
  misbehaving (oscillation, feedback loops). Validation Step 2d catches the
  *absence* of a threshold gate; threshold debug handles incorrect gate values.
- **`ha-4layer-presence`** — reference architecture for Steps 2a–2d. Read it
  when any Layer 1–4 structure is being built or modified.
