---
name: ha-presence-detection
description: >
  Use this skill whenever the user wants to build, design, debug, or extend a presence detection
  system in Home Assistant. Triggers include: "presence detection", "room occupancy", "person
  tracking", "state machine", "who is home", "room-level presence", "FSM", "occupancy automation",
  "motion sensor logic", "BLE presence", "mmWave occupancy", "person modeling", or any request
  to build automations that depend on knowing where a person is or whether a room is occupied.
  Also trigger when the user mentions layered presence architecture, confidence scoring, zone
  modeling, or debugging why a presence-based automation fired incorrectly. Use proactively
  whenever the user is working on automations that consume motion, mmWave, BLE, or device_tracker
  signals — even if they don't explicitly say "presence detection".
---

# Home Presence Detection Architecture Skill

A skill for building a layered, deterministic presence engine in Home Assistant + Node-RED + AppDaemon,
with full observability via InfluxDB and Grafana.

This is not "sensor triggers lights." This is a home state engine.

---

## Architectural Overview

The system is built in **7 layers**. Each layer has a single responsibility. Automations only
consume Layer 6 outputs — never raw signals. Each layer boundary is a contract.

```
Layer 0  Physical Sensors        (mmWave, PIR, BLE, door contacts, UniFi, cameras)
Layer 1  Raw Signal Entities     (normalized HA entities, no logic)
Layer 2  Signal Conditioning     (Node-RED: debounce, hold timers, RSSI filtering)
Layer 3  Room Presence FSM       (AppDaemon: per-room state machines)
Layer 4  Person Modeling         (AppDaemon: identity + location per person)
Layer 5  Zone Aggregation        (AppDaemon: downstairs_active, house_occupied, sleeping_mode)
Layer 6  Automation Interface    (the only entities automations may consume)
Layer 7  Observability           (InfluxDB events + Grafana dashboards)
```

**Core principles:**
- Stateless sensors, stateful engine
- No automation ever reads a raw sensor directly
- Everything observable in Grafana — you must be able to answer "why did this light turn on?"
- All logic Git-managed (AppDaemon = Python, Node-RED flows exported to Git)
- System degrades gracefully on sensor failure
- Every state transition fires an instrumented event

---

## Layer 0 — Physical Sensors

Hardware in use:
- Aqara FP2 / FP1S mmWave sensors
- Zigbee PIR sensors (via Zigbee2MQTT)
- BLE beacons (personal tracking)
- Door/window contact sensors
- UniFi client presence (UDMSE)
- Reolink / Frigate camera motion zones
- Pressure sensors (future)

No logic lives here. Hardware is interchangeable.

---

## Layer 1 — Raw Signal Layer

Each physical sensor maps to exactly one normalized HA entity.

### Naming Convention

```
binary_sensor.{room}_{sensor_type}_raw
sensor.{person}_{signal_type}_raw
```

Examples:
```yaml
binary_sensor.livingroom_mmwave_raw
binary_sensor.livingroom_pir_raw
binary_sensor.hallway_door_raw
sensor.aaron_ble_rssi_raw
binary_sensor.aaron_unifi_connected_raw
```

**Rules:**
- No automations consume this layer
- No time decay or logic
- Entity name always ends in `_raw`
- Represents physical truth only

---

## Layer 2 — Signal Conditioning Layer

Purpose: eliminate noise before it reaches the state machine.

### What lives here
- Debounce timers (5–30 seconds typical)
- Motion hold timers (keep `on` for N seconds after last trigger)
- RSSI threshold filtering (BLE signal strength gates)
- Entry/exit grace periods (door correlation windows)
- Rate limiting (suppress rapid flapping)

### Naming Convention

```
binary_sensor.{room}_{signal_type}_stable
binary_sensor.{room}_{context}
binary_sensor.{person}_{signal_type}_nearby
```

Examples:
```yaml
binary_sensor.livingroom_motion_stable
binary_sensor.livingroom_mmwave_stable
binary_sensor.frontdoor_recently_opened
binary_sensor.aaron_phone_nearby
binary_sensor.aaron_ble_home
```

### Implementation

**Preferred: Node-RED** — use delay nodes for hold timers, hysteresis nodes for RSSI thresholds.
Node-RED keeps this logic out of HA templates and makes it visually debuggable.

**Fallback: HA helpers + template sensors** — use `input_boolean` + automation for hold timers.

### Typical hold timer values (calibrate from InfluxDB data)
- PIR hold: 30–60 seconds
- mmWave hold: 10–20 seconds (more reliable, shorter hold needed)
- BLE RSSI gate: typically -75dBm threshold, 15s debounce
- Door "recently opened" window: 180 seconds

---

## Layer 3 — Room Presence State Machine

Each room is a deterministic FSM. This is where sensor fusion happens.

### States

```
vacant → maybe_occupied → occupied → confirmed_occupied → clearing → vacant
```

| State | Meaning |
|---|---|
| `vacant` | No presence detected |
| `maybe_occupied` | Single weak signal (possible walk-through or cat) |
| `occupied` | Multiple signals or sustained single signal |
| `confirmed_occupied` | Sustained presence for threshold period |
| `clearing` | No signals but not yet declared vacant |

### Standard Transition Logic

```
vacant → maybe_occupied
  WHEN: motion_stable = on (PIR or mmWave alone)

maybe_occupied → occupied
  WHEN: mmWave confirms OR second signal type triggers OR stable after X seconds

occupied → confirmed_occupied
  AFTER: N seconds of continuous presence (configurable per room)

occupied → clearing
  WHEN: all signals off for N seconds (configurable per room)

clearing → vacant
  AFTER: clearing_timeout expires with no new signals

clearing → occupied
  WHEN: any signal returns (re-entry detection)
```

### Cat Exclusion Rules

Ragdoll cats will trigger PIR. Never let PIR alone advance state:
- `maybe_occupied → occupied` requires mmWave OR door correlation OR BLE
- PIR-only events: max state is `maybe_occupied`
- mmWave with height/zone filtering preferred for cat rejection
- BLE absence confirms no human present even if PIR fires

### Output Entities

```yaml
sensor.{room}_presence_state        # full FSM state string
binary_sensor.{room}_occupied       # simplified true/false for automations
```

Examples:
```yaml
sensor.livingroom_presence_state     # "confirmed_occupied"
binary_sensor.livingroom_occupied    # true
sensor.bedroom_presence_state        # "vacant"
binary_sensor.bedroom_occupied       # false
```

### Implementation

**AppDaemon** — one `RoomFSM` class, instantiated per room via `apps.yaml` args. Python class
inherits from `hass.Hass`, registers state listeners in `initialize()`, restores state from
`input_select` backing store on startup.

**HA entity to store state:** use `input_select.{room}_presence_state` as the backing store so
state survives AppDaemon and HA restarts. AppDaemon reads this in `initialize()` to restore.

**Every transition must call `fire_transition_event()`** — see Observability section.

### Per-Room Timeout Configuration

Store timeouts as `input_number` helpers so they're tunable without code changes:
```yaml
input_number.livingroom_occupancy_timeout    # seconds before clearing
input_number.livingroom_clearing_timeout     # seconds in clearing before vacant
```

Calibrate defaults from InfluxDB — query actual occupancy duration distributions per room.

---

## Layer 4 — Person Modeling Layer

Maps identity to location. Separate from room occupancy.

### Person States

```
away → entering → home → in_room → sleeping → away
```

| State | Meaning |
|---|---|
| `away` | Not home |
| `entering` | Door opened + phone connected within window |
| `home` | Confirmed home, room unknown |
| `in_room` | Home + specific room identified |
| `sleeping` | In bedroom, late hour, no motion |

### Identity Signals (in priority order)

1. **BLE beacon RSSI** — most reliable for room-level location (strong, directional)
2. **UniFi WiFi presence** — home/away detection (UDMSE)
3. **Door event correlation** — entry/exit confirmation
4. **Room FSM state** — which confirmed_occupied room matches person's last known location
5. **Car presence** (future)
6. **Historical transition patterns** (Phase 3)

### Person Entity Naming

```yaml
sensor.{person}_presence_state       # full state: away/home/in_room/sleeping
sensor.{person}_location             # room name or "away" or "unknown"
binary_sensor.{person}_home          # simplified true/false
```

Examples:
```yaml
sensor.aaron_presence_state          # "in_room"
sensor.aaron_location                # "livingroom"
binary_sensor.aaron_home             # true
```

### Entry Detection Logic

```
IF phone connected to UniFi
AND frontdoor_recently_opened = true
THEN state = entering

IF entering
AND livingroom_occupied OR hallway_occupied
THEN state = in_room (location = relevant room)
```

### Implementation

**AppDaemon** — `PersonModel` class, one instance per person. Listens to Layer 2 conditioned
signals, door events, BLE RSSI, and UniFi presence. Writes results to Layer 6 entities.
**Every person state transition must fire an instrumented event** — see Observability section.

---

## Layer 5 — Zone Aggregation Layer

Aggregate room states into macro zones.

### Standard Zones

```yaml
binary_sensor.downstairs_active
binary_sensor.upstairs_active  
binary_sensor.house_occupied
input_select.house_mode          # "day", "evening", "sleeping", "away"
```

### Zone Logic Examples

```
downstairs_active = livingroom_occupied OR kitchen_occupied OR hallway_occupied OR diningroom_occupied

upstairs_active = bedroom_occupied OR office_occupied OR bathroom_occupied

house_occupied = any room occupied OR any person home

house_mode:
  sleeping = all persons sleeping
  away = house_occupied = false
  evening = time > 18:00 AND house_occupied
  day = default when occupied
```

---

## Layer 6 — Automation Interface

**The only entities automations may consume.**

```yaml
# Room level
binary_sensor.{room}_occupied

# Person level  
binary_sensor.{person}_home
sensor.{person}_presence_state
sensor.{person}_location

# Zone level
binary_sensor.downstairs_active
binary_sensor.house_occupied
input_select.house_mode
```

**Hard rule:** If an automation references any entity ending in `_raw` or `_stable`, it is wrong.
Refactor it to consume a Layer 6 entity.

This isolation means hardware can change (replace Aqara FP2 with different mmWave sensor)
without touching a single automation.

---

## Layer 7 — Observability (InfluxDB + Grafana)

You must be able to answer: *"Why did this light turn on?"* If you cannot, the architecture is wrong.

Observability is not optional. Build it in Phase 1 before writing any automations.

---

### Event Instrumentation in AppDaemon

Every state transition in Layers 3 and 4 fires a structured HA event. InfluxDB captures all
HA events automatically via the HA integration.

**Room FSM transitions:**
```python
def transition(self, new_state, trigger_source):
    self.fire_event("presence_fsm_transition",
        room=self.room,
        from_state=self.state.value,
        to_state=new_state.value,
        trigger=trigger_source,      # "pir", "mmwave", "ble", "timeout", "door"
        signals_active=self.active_signals(),   # list of currently active signals
        timestamp=self.datetime().isoformat()
    )
    # ... then do the transition
```

**Person model transitions:**
```python
self.fire_event("presence_person_transition",
    person=self.person,
    from_state=old_state,
    to_state=new_state,
    location=self.location,
    trigger=trigger_source,
    timestamp=self.datetime().isoformat()
)
```

Always log the transition in AppDaemon as well:
```python
self.log(f"[{self.room}] {old_state.value} → {new_state.value} (trigger: {trigger_source})")
```

---

### InfluxDB Schema

Events land in InfluxDB via the HA InfluxDB integration. Tag design is critical — tags are
indexed and used in Grafana filter variables.

**FSM transitions:**
```
measurement: presence_fsm_transition
tags:
  room:        livingroom
  from_state:  occupied
  to_state:    clearing
  trigger:     timeout
fields:
  value: 1            (event marker for counting)
  duration_ms: 4520   (time spent in from_state, optional)
```

**Person transitions:**
```
measurement: presence_person_transition
tags:
  person:      aaron
  from_state:  in_room
  to_state:    home
  location:    livingroom
  trigger:     ble_lost
fields:
  value: 1
```

**Raw signal events** (Layer 1 entities — captured automatically by InfluxDB HA integration):
```
measurement: binary_sensor.{room}_{sensor}_raw
tags:
  entity_id, domain, friendly_name
fields:
  value: 0 or 1
```

---

### Grafana Dashboard Layout

📄 **Full dashboard reference: `references/grafana.md`**

Read that file when building or modifying Grafana dashboards. It contains all 7 panel
definitions with Flux queries, colour mappings, and the full debugging workflow.

**Summary of the 7 rows:**

| Row | Panel | Purpose |
|---|---|---|
| 1 | Raw Signal Heatmap | Every `_raw` sensor over time — spot cat events and flapping |
| 2 | Room FSM State Timeline | Colour-coded presence state per room |
| 3 | Person Location Timeline | Where each person is modeled to be |
| 4 | Transition Event Log | Primary debug tool — filter by room, trigger, time |
| 5 | Cat False Positive Tracker | Count and trend of PIR-only events that didn't advance |
| 6 | Calibration Panel | Timeout distributions — use after 1 week to tune helpers |
| 7 | System Health | AppDaemon heartbeat, FSM activity rate, sensor availability |

**When to read `references/grafana.md`:**
- Building the Presence Engine dashboard for the first time
- Adding a new panel or row
- Writing or debugging a Flux query
- Following the debugging workflow for an unexpected automation trigger

---


## Confidence Scoring (Phase 2+)

Optional enhancement replacing binary signal fusion with weighted scoring.

```
livingroom_score:
  PIR active:          +20
  mmWave active:       +40
  BLE strong (< -65):  +30
  Door opened < 3min:  +10
  BLE medium (-75/-65):+15

Thresholds:
  score > 50  → occupied
  score 20-50 → maybe_occupied
  score < 20  → vacant
```

Advantage: new sensors just add a weight, no FSM logic changes needed.

---

## Failure Handling

The system must degrade gracefully, never collapse.

| Failure | Behavior |
|---|---|
| BLE unavailable | Remove BLE from scoring, fall back to motion + timeout |
| UniFi down | Person home/away uses last known state + door events |
| mmWave offline | Fall back to PIR-only, raise `maybe_occupied` max state |
| HA restart | AppDaemon reconnects automatically; FSM states restore from `input_select` backing store |
| AppDaemon restart | `initialize()` restores state from HA `input_select` entities |
| InfluxDB down | Presence engine continues; events queue in HA, observability temporarily blind |

---

## Implementation Phases

### Phase 1 (Current) — Vertical Slice
- [ ] Living room full stack (all 6 layers)
- [ ] Person model for Aaron only
- [ ] Downstairs zone
- [ ] Grafana pipeline visible
- [ ] All automations consuming Layer 6 only

### Phase 2 — Full Coverage
- [ ] All rooms with FSMs
- [ ] All persons modeled
- [ ] Confidence scoring replacing binary fusion
- [ ] Full Grafana dashboard

### Phase 3 — Intelligence
- [ ] Behavior learning (typical patterns per person)
- [ ] Predictive occupancy (pre-warm room before arrival)
- [ ] Anomaly detection

**Always build one vertical slice first.** Get living room right before scaling.

---

## Continuous Improvement Protocol

This skill improves over time as real data and real behaviour replace estimates and assumptions.
Claude Code must follow this protocol at the end of every presence detection session.

### End-of-Session Debrief

At the end of any session involving presence detection work — building, debugging, calibrating,
or extending — review what was done and check for learnings worth capturing.

If any of the following were discovered, output a `SKILL_UPDATE_PROPOSALS` block before closing:

- A timeout or threshold calibrated from real InfluxDB data (replaces a default estimate)
- An FSM edge case not covered in the documented transitions
- A cat false positive pattern that revealed a logic gap
- A Grafana query that proved more useful than the documented version
- An AppDaemon pattern that proved more reliable or cleaner than documented
- A sensor behaviour specific to Aaron's hardware (e.g. Aqara FP2 quirk)
- A room that needed non-standard FSM logic and why
- A failure mode encountered that isn't in the Failure Handling table

Output format:

```
SKILL_UPDATE_PROPOSALS:
- Section: [exact section name in skill]
  Change: [what to update or add]
  Reason: [what was learned]
  Evidence: [InfluxDB result / observed behaviour / log output]

- Section: [another section]
  Change: [...]
  Reason: [...]
  Evidence: [...]
```

Aaron reviews and approves each proposal. On approval, update the SKILL.md file directly.

### Calibration Update Trigger

Whenever a Grafana calibration query is run (Row 6 of the Presence Engine dashboard), update
the Calibrated Values Registry table below with the measured values. Replace `—` with real
numbers. Add the date. This is the most important improvement loop — defaults become actuals.

### Room Graduation

When a room completes the full 12-step implementation workflow and has at least one week of
InfluxDB data, mark it as `live` in the Live Room Registry below and fill in its calibrated values.

---

## Calibrated Values Registry

Values below are measured from InfluxDB data, not estimates. Defaults are initial guesses only.
Update this table after running the Grafana calibration panel (Row 6) for each room.

**Last updated:** —

| Room | PIR hold (s) | mmWave hold (s) | Confirm timeout (s) | Clearing timeout (s) | Status |
|---|---|---|---|---|---|
| livingroom | 30 | 10 | 60 | 45 | — |
| kitchen | 30 | 10 | 60 | 45 | — |
| hallway | 30 | 10 | 30 | 30 | — |
| bedroom | 30 | 10 | 120 | 60 | — |
| office | 30 | 10 | 120 | 60 | — |
| bathroom | 30 | 10 | 30 | 120 | — |

Status values: `—` (not started) → `building` → `live` → `calibrated`

**BLE RSSI Thresholds (per person):**

| Person | Home threshold (dBm) | Room threshold (dBm) | Away timeout (s) | Last calibrated |
|---|---|---|---|---|
| aaron | -85 | -70 | 120 | — |

**Cat Exclusion Observed Patterns:**

Record confirmed cat false positive events here as they are discovered. This informs
future rule tightening.

| Date | Room | Time of day | Signals active | FSM reached | Resolution |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

---

## Live Room Registry

Tracks implementation status per room. Update as rooms progress through phases.

| Room | Floor | Phase | FSM live | Grafana live | Calibrated | Notes |
|---|---|---|---|---|---|---|
| livingroom | Ground | 1 | — | — | — | Pilot room — implement first |
| kitchen | Ground | 1 | — | — | — | |
| hallway | Ground | 1 | — | — | — | |
| bedroom | First | 2 | — | — | — | |
| office | First | 2 | — | — | — | |
| bathroom | First | 2 | — | — | — | |

Add rooms as they are discovered during the naming audit.

---

## Anti-Patterns — Never Do These

- Trigger lights directly from PIR
- Mix identity logic and room occupancy in the same automation
- Put FSM logic in HA templates or Node-RED (use AppDaemon)
- Skip logging state transitions — observability is not optional
- Hardcode timeouts in automations (use `input_number` helpers, calibrate from InfluxDB)
- Reference `_raw` or `_stable` entities in automations
- Let a single sensor be authoritative for occupancy
- Write automations before the Grafana pipeline is verified working
- Fire events without a `trigger` field — you lose the ability to debug why a transition happened

---

## Workflow for Implementing a New Room

1. **Audit sensors** — query HA MCP to list all entities in the target room area
2. **Identify Layer 0 hardware** — what physical sensors exist
3. **Create Layer 1 entities** — rename/normalize to `_raw` convention
4. **Build Layer 2 conditioning** — Node-RED flows with hold timers per sensor type
5. **Query InfluxDB** — get actual occupancy duration data to calibrate timeouts (if data exists)
6. **Build Layer 3 FSM** — AppDaemon `RoomFSM` class, add room entry to `apps.yaml`
7. **Add `fire_event` instrumentation** — every transition fires `presence_fsm_transition`
8. **Create Layer 6 outputs** — `binary_sensor.{room}_occupied` + `sensor.{room}_presence_state`
9. **Verify Grafana pipeline** — confirm events appearing in InfluxDB and FSM timeline panel before continuing
10. **Write automations** — consuming Layer 6 only
11. **Test cat exclusion** — verify PIR-alone doesn't advance past `maybe_occupied`
12. **Calibrate timeouts** — after 1 week of data, use Grafana calibration panel to tune `input_number` helpers

---

## Key Entity Reference

```yaml
# Raw sensors (Layer 1) — never used in automations
binary_sensor.{room}_mmwave_raw
binary_sensor.{room}_pir_raw
binary_sensor.{room}_door_raw
sensor.{person}_ble_rssi_raw

# Conditioned signals (Layer 2) — never used in automations
binary_sensor.{room}_motion_stable
binary_sensor.{room}_mmwave_stable
binary_sensor.{person}_phone_nearby

# Room FSM (Layer 3) — never used directly in automations
sensor.{room}_presence_state
input_select.{room}_presence_state   # backing store

# Automation interface (Layer 6) — ONLY these in automations
binary_sensor.{room}_occupied
binary_sensor.{person}_home
sensor.{person}_presence_state
sensor.{person}_location
binary_sensor.downstairs_active
binary_sensor.house_occupied
input_select.house_mode
```

