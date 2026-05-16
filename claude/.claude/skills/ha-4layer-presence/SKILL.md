---
name: ha-4layer-presence
description: >
  Use this skill when building, debugging, or extending presence-based lighting
  automation in Home Assistant using the native four-layer architecture. Triggers
  include: "four-layer", "state machine", "presence lighting", "occupancy state",
  "lighting mode", "scene execution", "Layer 2", "Layer 3", "Layer 4", "transit
  zone", "dwell zone", "cooldown", "lux gating", "sleep mode", "manual override",
  "bedtime shutdown", "input_select", "occupancy_state_machine", or any request
  to build or modify room lighting automations that respond to presence sensors.
  Also trigger when debugging why a lighting mode did not change, why a light
  fired at the wrong time, or why a cooldown did not behave correctly. Use
  proactively for any room where the goal is: presence on → lights on, presence
  off → lights off after delay.
---

# HA Four-Layer Presence Lighting Architecture

Pure Home Assistant native implementation — no Node-RED, no AppDaemon.
All state lives in `input_select` helpers. All logic lives in HA automations.
Everything is inspectable in the HA developer tools.

This is the reference architecture for the home automation project at
`~/Documents/CLAUDE/Home_Automation/presence-lighting/CLAUDE.md`.

---

## The Four Layers

```
Layer 1: Sensor fusion      Raw sensors → binary_sensor.{room}_presence
Layer 2: State machine      binary_sensor → input_select.{room}_occupancy_state
Layer 3: Lighting mode      occupancy_state → input_select.{room}_lighting_mode
Layer 4: Scene execution    lighting_mode → actual light service calls
```

Each layer has one responsibility. Automations only read the layer immediately
below them — never raw sensors directly.

**The boundary between layers is the contract.** Replacing Layer 3 mode logic
does not require changing Layer 4. Replacing the Layer 2 state machine does not
require changing Layer 3.

---

## Two Archetypes: Dwell Zones vs Transit Zones

### Dwell Zone (living room, office)

Rooms where people stay for extended periods. Uses a full five-state machine with
confirmation and leaving timers to prevent false positives from brief transits.

**States:** `idle → detecting → occupied → leaving → cooldown → idle`

| Transition | Trigger | Timer |
|-----------|---------|-------|
| idle → detecting | presence on | Start confirmation timer (8s) |
| detecting → occupied | confirmation timer finished | — |
| detecting → idle | presence off before timer | Cancel timer |
| occupied → leaving | presence off | Start vacancy timer (60s) |
| leaving → occupied | presence on (re-entry) | Cancel vacancy timer |
| leaving → cooldown | vacancy timer finished | Start cooldown timer (30s) |
| cooldown → occupied | presence on (re-entry) | Cancel cooldown timer |
| cooldown → idle | cooldown timer finished | — |

**Key design:** `detecting` and `leaving` states hold last mode — no light changes
during transitions. This prevents flicker during brief movements.

### Transit Zone (hallway, landing, bathroom)

Rooms people pass through quickly. No confirmation delay — lights must be instant.
Simpler three-state machine.

**States:** `idle ↔ occupied ↔ cooldown`

| Transition | Trigger | Timer |
|-----------|---------|-------|
| idle → occupied | presence on | — |
| occupied → cooldown | presence off | Start cooldown timer |
| cooldown → occupied | presence on (re-entry) | Cancel cooldown timer |
| cooldown → idle | cooldown timer finished | — |

**Key design:** No `detecting` state — lights on immediately. No `leaving` state —
cooldown starts immediately on presence off.

**Cooldown durations by room type:**
- Hallway: 60s (transit, rarely pauses)
- Landing: 45s (transit, slightly shorter — quick pass-through at top of stairs)
- Bathroom: 90s (extended — occupant may be still, sensor may miss motionless person)

---

## Layer 1 — Sensor Fusion

Layer 1 produces `binary_sensor.{room}_presence` — a single fused signal.

**Creation method:** HA UI → Settings → Helpers → Add Helper → Template → Binary Sensor.
Template sensors CANNOT be created via MCP API (`ha_create_config_entry_helper` with
`template_type: binary_sensor` returns `VALIDATION_FAILED`).

**Standard fusion formula (OR logic):**
```jinja2
{{ is_state('binary_sensor.sensor_a', 'on')
   or is_state('binary_sensor.sensor_b', 'on') }}
```

**Provide the exact Jinja2 formula to the user** and instruct them to create the
helper manually. Do not attempt to create template sensors via MCP.

---

## Layer 2 — State Machine Automation

**Automation mode:** `queued` with `max: 5` — ensures rapid trigger sequences
don't drop transitions.

**Timer trigger pattern (critical — do not use state triggers for timers):**

```yaml
trigger:
  - trigger: state
    entity_id: binary_sensor.{room}_presence
  - trigger: event
    event_type: timer.finished
    event_data:
      entity_id: timer.{room}_occupancy_cooldown
```

Use `event_type: timer.finished` — not `trigger: state` on the timer entity.
The `idle` state briefly appears when a timer is cancelled, causing spurious triggers
if you watch the timer entity state. The `timer.finished` event only fires on natural
completion, not cancellation.

**State machine skeleton (transit zone):**

```yaml
alias: "{Room} Occupancy State Machine"
mode: queued
max: 5
trigger:
  - trigger: state
    entity_id: binary_sensor.{room}_presence
  - trigger: event
    event_type: timer.finished
    event_data:
      entity_id: timer.{room}_occupancy_cooldown
action:
  - choose:
    # Presence ON → occupied
    - conditions:
        - condition: trigger
          id: ...
        - condition: state
          entity_id: binary_sensor.{room}_presence
          state: "on"
      sequence:
        - action: timer.cancel
          target:
            entity_id: timer.{room}_occupancy_cooldown
        - action: input_select.select_option
          target:
            entity_id: input_select.{room}_occupancy_state
          data:
            option: occupied
    # Presence OFF from occupied → start cooldown
    - conditions:
        - condition: state
          entity_id: binary_sensor.{room}_presence
          state: "off"
        - condition: state
          entity_id: input_select.{room}_occupancy_state
          state: occupied
      sequence:
        - action: timer.start
          target:
            entity_id: timer.{room}_occupancy_cooldown
        - action: input_select.select_option
          target:
            entity_id: input_select.{room}_occupancy_state
          data:
            option: cooldown
    # Re-entry during cooldown → back to occupied
    - conditions:
        - condition: state
          entity_id: binary_sensor.{room}_presence
          state: "on"
        - condition: state
          entity_id: input_select.{room}_occupancy_state
          state: cooldown
      sequence:
        - action: timer.cancel
          target:
            entity_id: timer.{room}_occupancy_cooldown
        - action: input_select.select_option
          target:
            entity_id: input_select.{room}_occupancy_state
          data:
            option: occupied
    # Timer finished → idle
    - conditions:
        - condition: trigger
          id: ...  # timer.finished event trigger
      sequence:
        - action: input_select.select_option
          target:
            entity_id: input_select.{room}_occupancy_state
          data:
            option: idle
```

---

## Layer 3 — Lighting Mode

**Automation mode:** `restart` — always re-evaluates with current conditions
when any relevant input changes.

**Triggers:** `{room}_occupancy_state` changes, `sleep_mode` changes, lux sensor
crosses threshold (numeric_state above/below), time patterns for any fixed boundaries.

**Standard mode priority (dwell zone with all features):**

| Priority | Condition | Mode |
|----------|-----------|------|
| 1 | occupancy_state = idle | `off` |
| 2 | occupancy_state = cooldown | `dim` (always — visual fade-out cue) |
| 3 | occupied + sleep_mode = on + time < 07:00 | `sleep` |
| 4 | occupied + tv_mode = on | `movie` |
| 5 | occupied + time 22:00–07:00 | `dim` |
| 6 | occupied + lux < 20 lx | `bright` |
| 7 | occupied (default) | `normal` |

**Standard mode priority (transit zone with lux + time gates):**

| Priority | Condition | Mode |
|----------|-----------|------|
| 1 | occupancy_state = idle | `off` |
| 2 | occupancy_state = cooldown + lux ≥ threshold | `off` (mirrors occupied lux gate — no phantom fade-out when lights were never on) |
| 3 | occupancy_state = cooldown | `dim` (visual fade-out — only fires when lights were actually on) |
| 4 | occupied + sleep_mode + time < 07:00 | `night` |
| 5 | occupied + 07:00–20:00 + lux ≥ threshold | `off` (natural light) |
| 6 | occupied + 07:00–20:00 | `normal` |
| 7 | occupied + 20:00–07:00 | `night` |

**Key rules:**
- Cooldown lux gate must mirror the occupied lux gate — if lux ≥ threshold kept lights off during occupied, cooldown must also go to `off`, not `dim`. A fade-out on lights that were never on is wrong.
- Cooldown → `dim` is the visual fade-out cue and only makes sense when lights were actually on
- Sleep_mode on + time ≥ 07:00 → time rule applies (07:00 always wins the morning)
- Night mode (time-gated) bypasses the lux gate — lux doesn't matter after 20:00

### Lux Gating

**When to add lux gating:** Any room with a window that receives meaningful daylight.
Mandatory for hallways, landings, bathrooms with windows.

**How to add lux numeric_state triggers:**
```yaml
trigger:
  - trigger: numeric_state
    entity_id: sensor.{room}_illuminance
    above: 50   # threshold in lx
  - trigger: numeric_state
    entity_id: sensor.{room}_illuminance
    below: 50
```

**Thresholds:**
- Downstairs hallway: **no lux gate** — replaced with sun gate (`sun.sun above_horizon → off`). Original 50 lx threshold caused oscillation (ambient 43 lx, lights-on 68 lx). InfluxDB showed daytime peaks of 100–13,000 lx; sun gate is reliable and oscillation-free.
- Landing: 20 lx (MSR-2 lux sensor)
- Main bathroom: **no lux gate** — interior room reads 39 lx midday (lights off). 40 lx threshold was tried and caused feedback oscillation (lights pushed sensor to 47–90 lx → off → 39 lx → on → loop). Interior rooms where ambient is always low are legitimate exceptions — document the reason.
- Adjust based on sensor readings at the target crossover point

**Lux feedback loop risk:** When the room light turns on, it may push lux above
the threshold → Layer 3 switches to `off` → lights out → lux drops → lights back on.
This is a real risk — monitor after commissioning. **Before setting any threshold,
query InfluxDB to understand the sensor's real range across multiple days.** Use the
`ha-sensor-threshold-debug` skill for the full diagnostic workflow: oscillation zone
maths, fix options (remove gate / sun gate / raise threshold / hysteresis), and
InfluxDB query patterns. Do not guess thresholds from current state alone.

---

## Layer 4 — Scene Execution

**Automation mode:** `restart`

**Trigger:** `{room}_lighting_mode` state changes.

**Pattern:** Choose block with one branch per mode. Each branch calls `light.turn_on`
or `light.turn_off` directly with explicit `brightness_pct`, `color_temp_kelvin`,
and `transition` parameters.

**Do not use HA scenes in Layer 4 unless you have verified their entity lists.**
`scene.living_room_bright` and `scene.living_room_dim` contain stale entity IDs
(`light.lr_spot_*` — renamed to `light.living_room_spot_*`). Scenes fail silently
when referenced entities no longer exist. Always call lights directly.

**Standard light mapping (transit zone):**

```yaml
action:
  - choose:
    - conditions:
        - condition: state
          entity_id: input_select.{room}_lighting_mode
          state: "off"
      sequence:
        - action: light.turn_off
          target:
            entity_id: light.{room}_light
          data:
            transition: 1

    - conditions:
        - condition: state
          entity_id: input_select.{room}_lighting_mode
          state: dim
      sequence:
        - action: light.turn_on
          target:
            entity_id: light.{room}_light
          data:
            brightness_pct: 30
            color_temp_kelvin: 2700
            transition: 1

    - conditions:
        - condition: state
          entity_id: input_select.{room}_lighting_mode
          state: normal
      sequence:
        - action: light.turn_on
          target:
            entity_id: light.{room}_light
          data:
            brightness_pct: 80
            color_temp_kelvin: 3000
            transition: 1

    - conditions:
        - condition: state
          entity_id: input_select.{room}_lighting_mode
          state: night
      sequence:
        - action: light.turn_on
          target:
            entity_id: light.{room}_light
          data:
            brightness_pct: 15
            color_temp_kelvin: 2000   # warmest supported on RGBW lights — candlelight amber
            transition: 1
```

**Night mode colour:** 2000K at 15% is warm amber / candlelight — not harsh on eyes
for 2am trips. Only achievable on RGBW lights with ≤ 2000K range (e.g. hallway upstairs
light). Standard warm-white lights bottom out at 2700K.

---

## Manual Override (Open Plan / Dwell Zones)

Allows manual scene selection to coexist with presence automation.

**Helper:** `input_select.{zone}_manual_override` with states:
`auto / freeze / dim / bright / off`

**Override timer:** `timer.{zone}_override_expiry` — 8 hours. Auto-resets to `auto`.

**Layer 3 behaviour when override ≠ auto:**

| Override | Effect |
|----------|--------|
| `auto` | Normal — state machine runs |
| `freeze` | Hold current lights — no mode changes |
| `dim` | Force dim — ignore presence |
| `bright` | Force bright — ignore presence |
| `off` | Force off — hard override |

**Scene scripts set override to `freeze`** after adjusting lights — prevents Layer 3
fighting the manual scene. The 8h timer resets to `auto` automatically.

---

## Whole-House Bedtime Shutdown

Sits above the room-level stacks. Not a four-layer automation — a separate modular
script system orchestrated by a trigger automation.

### Trigger

`automation.bedtime_shutdown_trigger` watches `binary_sensor.bed_presence_ac5280_bed_occupied_right`
(right/Aaron's side) going `on` for 5 seconds within time window 22:00–02:00.

**Why right side only:** Right side = Aaron's side. Child may be in bed (left) before
Aaron goes upstairs — triggering on "either side" would produce a spurious house
shutdown while Aaron is still downstairs. See ADR 010.

### Script Architecture

```
script.bedtime_shutdown (orchestrator)
  ├── script.bedtime_security_check → status dict
  ├── script.bedtime_lighting → status dict
  ├── script.bedtime_climate → status dict
  └── script.bedtime_appliances_check → status dict
```

Each sub-script returns a `script_result` dict:
```yaml
stop: "done"
response_variable: script_result
# script_result contains:
#   status: "all_clear" | "needs_attention"
#   actioned: "string of actions taken"
#   flagged: "string of issues found"
```

Orchestrator combines `flagged` strings, sends:
- TTS: always
- Phone push: only if `needs_attention`

**Critical — sub-scripts must always reach their `stop:` step.** If a sub-script
errors before `stop:`, the orchestrator's `response_variable` is never set, and
the orchestrator silently halts when it accesses `foo.status`. Rule: any action
in a sub-script that could fail must have `continue_on_error: true`. Best-effort
cleanup actions (media players, optional devices) are the main risk area.

**`media_player.turn_off` is unreliable.** Entities can be `standby/idle/off/playing`
and still reject `turn_off`. Checking `not is_state(..., 'unavailable')` is
insufficient. Always add `continue_on_error: true` to media player steps.

---

## Entity Naming Conventions

| Layer | Pattern | Example |
|-------|---------|---------|
| Raw sensor | `binary_sensor.{device}_{zone}` | `binary_sensor.apollo_r_pro_1_w_35c658_ld2450_presence` |
| Layer 1 fused | `binary_sensor.{room}_presence` | `binary_sensor.living_room_presence` |
| State machine | `input_select.{room}_occupancy_state` | `input_select.hallway_occupancy_state` |
| Lighting mode | `input_select.{room}_lighting_mode` | `input_select.hallway_lighting_mode` |
| Cooldown timer | `timer.{room}_occupancy_cooldown` | `timer.landing_occupancy_cooldown` |
| State machine automation | `automation.{room}_occupancy_state_machine` | — |
| Lighting mode automation | `automation.{room}_lighting_mode` | — |
| Scene execution automation | `automation.{room}_scene_execution` | — |

Room names in entity IDs: `living_room`, `dining`, `kitchen`, `hallway`, `snug`,
`master_bedroom`, `office`, `isabellas_bedroom`, `landing`, `main_bathroom`,
`master_bathroom`, `downstairs_wc`

---

## Pre-Build Checklist (per room)

Before building any room's stack:

1. **Verify the fused sensor exists.** `ha_get_state('binary_sensor.{room}_presence')`.
   If missing, provide Jinja2 formula and instruct user to create via HA UI.

2. **Check for adaptive lighting.** Search for `switch.adaptive_lighting_*` on the
   room's lights. If found, disable before Layer 4 goes live — adaptive lighting
   continuously overrides `color_temp` and `brightness`, silently undoing Layer 4 calls.

3. **Identify existing automations.** Search for old automations that control the same
   lights. Disable them (not delete) as part of commissioning. Document in Implementation Log.

4. **Confirm light entity capabilities.** Check `color_temp_kelvin` range, RGBW support,
   group vs individual. Don't target unavailable group entities.

5. **Check for lux sensor.** If room has windows, identify the illuminance sensor entity
   before designing Layer 3. FP300 devices provide `sensor.{room}_p300_illuminance`.
   FP2 devices provide a light level binary sensor. Apollo MSR-2 provides `sensor.{device}_ltr390_light`.

6. **Verify InfluxDB include list covers the new room's entities.** The HA InfluxDB
   integration (api_version: 2) requires `include: domains: [input_select, input_boolean]`
   in `configuration.yaml` — entity-level `include: entities:` alone does NOT subscribe
   to state change events for helper domains. Binary sensors work with entity-level include.
   If these domains are already in `include: domains:`, no change needed. If adding a new room
   also adds new entity types, restart HA after updating `configuration.yaml`.

---

## MCP Tooling Notes

**`ha_config_set_automation` parameter names:**
- Takes `config` (not `automation_config`)
- Takes `identifier` (not `automation_id`) for updates
- Wrong names produce Pydantic validation error

**`ha_config_set_helper` for `input_select`:**
- Parameters: `name`, `options`, `icon`, `initial`
- No `friendly_name` parameter — using it causes validation error
- `name` becomes both entity ID suffix and display name

**`ha_get_automation_traces` for debugging:**
- Parameter is `automation_id` (works for scripts too)
- Always check traces first when debugging — error messages are exact
- Script completing in ~25ms is normal; check `ha_get_state` on lights, not trace timing

**`ha_call_service` parameter structure:**
```python
ha_call_service("light", "turn_on",
    entity_id="light.foo",
    data={"brightness_pct": 80, "color_temp_kelvin": 3000})
```
- `entity_id` and `data` are separate top-level parameters
- Not `service_data`

---

## Patterns & Pitfalls

**Scenes fail silently on stale entity IDs.**
Scenes skip missing entities without error. `scene.living_room_bright` and
`scene.living_room_dim` have stale `light.lr_spot_*` IDs (renamed to
`light.living_room_spot_*`). Always call lights directly in new Layer 4 code.
When using existing scenes in Layer 4, verify entity lists first.

**`detecting` and `leaving` states must be no-ops in Layer 3.**
During transitions, Layer 3 should hold last mode rather than switching to `off`.
Otherwise lights briefly cut out whenever someone pauses or re-enters. Implement
by adding `detecting` and `leaving` as explicit no-op cases in the Layer 3 choose
block (sequence: []).

**Cooldown lux gate must mirror the occupied lux gate.**
If lux ≥ threshold kept lights off during occupied (no phantom turn-on), cooldown
must also go to `off` — not `dim`. The fade-out only makes sense when lights were
actually on. Pattern: `cooldown + lux ≥ threshold → off` before the unconditional
`cooldown → dim`. This was a recurring bug found on landing and downstairs hallway.

**Template sensor creation requires the user.**
`ha_create_config_entry_helper` with `template_type: binary_sensor` fails with
`VALIDATION_FAILED`. The workaround is HA UI creation. Provide the exact Jinja2
formula and walk the user through Settings → Helpers → Add Helper → Template →
Binary Sensor.

**Old-style `group.set` is sufficient for dashboard light groups.**
Only reach for a `light.` domain group if you need inline brightness/colour control
on the group tile itself. `ha_create_config_entry_helper` fails for the group type
anyway — use `ha_call_service("group", "set", {...})` to create old-style groups.

**`ha_call_service` result `[]` is normal for light services.**
Empty result array = service dispatched, no return value expected. Not an error.

**Nocturnal vetoes must not rely on `sleep_mode` alone.**
`sleep_mode` clears when Aaron gets up briefly (bathroom, water). If he returns to bed,
`sleep_mode` stays off but `bed_presence` goes back on. A veto of
`sleep_mode=on AND bed=on` becomes fully inactive after that brief exit — cats trigger
freely for the rest of the night. Always pair with a time gate:

```jinja2
and not (is_state('binary_sensor.bed_presence_ac5280_bed_occupied_right', 'on')
         and (is_state('input_boolean.sleep_mode', 'on')
              or (now().hour >= 0 and now().hour < 8)))
```

In HA Layer 2 automation conditions (hallway pattern):
```yaml
condition: not
conditions:
  - condition: and
    conditions:
      - condition: state
        entity_id: binary_sensor.bed_presence_ac5280_bed_occupied_right
        state: "on"
      - condition: or
        conditions:
          - condition: state
            entity_id: input_boolean.sleep_mode
            state: "on"
          - condition: time
            after: "00:00:00"
            before: "08:00:00"
```

`now().hour` and HA `time:` conditions use the HA configured timezone (Europe/Berlin,
UTC+1 in winter). `hour < 8` Berlin = before 07:00 UK in winter, before 08:00 UK in
summer. The bed sensor is the real discriminator — if Aaron gets up for real, bed=off
releases the veto regardless of time. The time gate only matters when he goes back to bed.

**HA history API times out for high-frequency `input_select` entities.**
`ha_get_history` with a 7–10 day window on `input_select.{room}_occupancy_state`
regularly times out — these entities log every state transition and generate thousands
of rows. Use InfluxDB Flux queries instead:

```flux
from(bucket: "home_assistant")
  |> range(start: -7d)
  |> filter(fn: (r) => r["entity_id"] == "open_plan_occupancy_state")
  |> filter(fn: (r) => r["_field"] == "state")
```

`ha_get_history` works fine for lower-frequency entities (lighting_mode, bed_presence,
sleep_mode — use those via HA history; use InfluxDB for occupancy_state).

---

## Comfort Auditing

When presence-based lighting "feels wrong" — lights go off while someone is present —
use this methodology to measure the problem before changing anything.

### Comfort failure metric

**Definition:** `occupancy_state` transitions `idle → occupied/detecting` within N minutes
of the previous `idle` transition. The gap from going idle to being re-triggered is the
discomfort window. N=3 minutes is a good starting threshold.

**What it tells you:**
- Gap < 90s: lights went off and came back almost immediately — timer too short or sensor
  losing and re-acquiring rapidly (sensor quality issue)
- Gap 90s–3min: lights went off, person had to wave — timer borderline
- Gap > 3min: not a comfort failure by this metric (person may have genuinely left)

**Signal to pull:** `input_select.{room}_occupancy_state` via InfluxDB (not HA history —
see above). Count sequences where `idle` → `occupied/detecting` gap ≤ 3 min.

### Leaving↔occupied bounce ratio

Count total `leaving` transitions ÷ total completed sessions (idle entries).
This is the average number of times the sensor lost and re-acquired presence per session.

- Ratio ~1.0: healthy — one leaving transition per session, sensor holds presence
- Ratio 2–3: sensor frequently losing stationary presence, re-acquiring within leaving window
- Ratio > 3: significant sensor instability — investigate sensor placement/thresholds

**Computed in 2026-03-23 audit:**
- Open plan: 715 leaving / 308 idle = **2.3×** — LD2450/LD2412 losing stationary persons
- Hallway: 835 occupied = 835 sessions (transit zone, no leaving state) — healthy

### Leaving timer is the primary comfort dial for dwell zones

The leaving timer determines how long the state machine waits before transitioning
`occupied → cooldown`. Extending it absorbs most sensor bounce-backs without requiring
sensor reconfiguration.

Typical starting values and what to change to:
- 60s → 120s: handles sensors that briefly lose stationary targets (LD2450 motion-first)
- 120s → 180s: if comfort failures persist after 120s, investigate sensor before extending further

Extending beyond 180s without understanding the sensor problem means lights stay on
for 3+ minutes after genuine departure — efficiency cost becomes noticeable.

The total time from last detection to lights off = `leaving_timer + cooldown_timer`.
At 120s + 30s = 150s total. At the original 60s + 30s = 90s — marginal for any sensor
that needs more than one scan cycle to re-acquire a still person.
