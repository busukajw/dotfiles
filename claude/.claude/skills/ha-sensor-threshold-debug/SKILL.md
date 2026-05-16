---
name: ha-sensor-threshold-debug
description: >
  Use this skill when debugging why a Home Assistant automation is flickering,
  oscillating, cycling on and off, or behaving erratically in response to a
  numeric sensor (lux, temperature, humidity, CO2, etc.). Triggers include:
  "flickering", "cycling", "oscillating", "turning on and off repeatedly",
  "lights keep changing", "sensor threshold", "lux gate", "why does it keep
  firing", or any situation where an automation triggers repeatedly in a short
  window on a numeric_state trigger. Also trigger proactively when setting a
  new numeric threshold — always check InfluxDB range data before committing
  to a value.
---

# HA Sensor Threshold Debugging

Patterns and diagnostic workflow for numeric sensor thresholds in HA automations.
Derived from real oscillation bugs in this project — lux gating in the bathroom,
landing, and hallway all hit variants of this problem.

---

## The Core Problem: Sensor Feedback Loops

An automation that turns on a device in response to a sensor reading can create
a feedback loop if that device affects the sensor it reads from.

**Classic pattern:**
1. Sensor reads low → automation turns device ON
2. Device pushes sensor reading high → automation turns device OFF
3. Sensor drops back → automation turns device ON again
4. Repeat indefinitely — visible as rapid on/off cycling

**This project's recurring example:**
- Hallway light (80% brightness) adds ~25 lx to the FP2 lux sensor reading
- Ambient lux ~43 lx (evening) → lights on → sensor reads 68 lx → above 50 lx threshold → lights off → sensor reads 43 lx → below 50 lx → lights on → repeat

The device doesn't have to fully explain the sensor reading — even a partial
contribution is enough to cause oscillation if the threshold sits in the
contribution range.

---

## Diagnostic Workflow

Follow these steps in order. Do not skip to fixes.

### Step 1 — Pull automation traces

```
ha_get_automation_traces("automation.{room}_lighting_mode", limit=20)
```

Look for:
- Multiple traces in a short window (seconds apart = oscillation, not coincidence)
- Which **trigger** is firing — is it the occupancy state change, or the numeric sensor?
- What **values** the sensor was at when each trigger fired (visible in `to_state` / `from_state`)

If the lux (or other numeric) trigger is firing repeatedly, that's the loop. If the
occupancy trigger is firing repeatedly, the problem is in Layer 2 (sensor debounce —
see `ha-4layer-presence` skill).

### Step 2 — Query InfluxDB for historical sensor range

**Always do this before changing any threshold.** A single trace gives you one
data point. InfluxDB gives you the real distribution.

```flux
from(bucket: "home_assistant")
  |> range(start: -7d)
  |> filter(fn: (r) => r["entity_id"] == "{sensor_entity_id}")
  |> filter(fn: (r) => r["_field"] == "value")
  |> aggregateWindow(every: 1h, fn: max, createEmpty: false)
```

**InfluxDB connection:** org = `homeautomation`, bucket = `home_assistant`

What to look for:
- **Nighttime baseline** (device off, no other sources): what is the sensor floor?
- **Device-on contribution**: what does the sensor read when the device is running?
  The difference between baseline and device-on is the **feedback contribution**.
- **Daytime / target-condition range**: what does the sensor read when you genuinely
  want the device OFF? Is there a clear gap above the device-on reading?
- **Transition zone**: when does the sensor cross from "device needed" to "device not needed"?
  What time of day, what readings?

### Step 3 — Calculate the oscillation zone

The oscillation zone is any threshold value where:

```
sensor_baseline < threshold < sensor_baseline + device_contribution
```

If your threshold sits in this range, oscillation is guaranteed whenever ambient
conditions are at or near the baseline.

**Example from hallway:**
- Baseline (no light): 43 lx
- Device contribution (hallway light at 80%): +25 lx → 68 lx with light on
- Original threshold: 50 lx
- Oscillation zone: 43 < 50 < 68 ✓ → guaranteed oscillation

**Safe threshold:** must be either below the baseline (always trigger) or above
`baseline + contribution` (never trigger under those conditions).

### Step 4 — Identify the right fix

See fix options below.

---

## Fix Options (ranked by complexity)

### Option A — Remove the gate entirely

Use when: the sensor is so affected by the device that it cannot give a reliable
independent reading in the ambient range that matters. Interior rooms with no
windows are the common case.

**Example:** Main bathroom — FP300 lux sensor reads 39 lx ambient at midday.
Room always needs light regardless of time of day. Lux gate adds no value; removed.

### Option B — Switch to a non-feedback signal

Use when: you want environmental gating but the sensor itself is unreliable.
Best alternatives:
- **`sun.sun` state** (`above_horizon` / `below_horizon`) — no feedback possible,
  accounts for seasons. Good for rooms that track daylight naturally.
- **Time-of-day condition** — explicit windows (07:00–22:00). Predictable but
  doesn't adapt to seasons or weather.

**Example:** Downstairs hallway — lux oscillated (43 lx ambient, 68 lx with light,
threshold 50 lx). Replaced with sun gate: `occupied + sun above_horizon → off`.
InfluxDB confirmed daytime readings of 100–13,000 lx on bright days, so sun position
correlates well with "don't need lights".

**Sun gate caveat:** `above_horizon` flips exactly at sunset. In UK summers, sunset
is 21:00+. If you need earlier activation, use `condition: sun` with `after_offset`.

### Option C — Raise the threshold above the feedback zone

Use when: the device contribution is small relative to the genuine daytime range,
and there is a clear gap between device-on readings and conditions where you want
the gate active.

**Requirement:** threshold must be > `max(device-on reading in conditions where gate
should be inactive)`. Use InfluxDB data to verify the gap exists.

**Oscillation check:** even after raising the threshold, verify the new danger zone
(`threshold - contribution` to `threshold`) doesn't overlap with real ambient readings.

**Example:** If device-on max = 93 lx and daytime min = 150 lx, threshold of 120 lx
is safe. If daytime min is 95 lx, threshold of 120 lx still oscillates (95 < 120 < 120).

### Option D — Add hysteresis (two thresholds)

Use when: you need lux-based gating and there is no clean gap that allows a single
threshold. Requires two separate numeric_state triggers with different values.

**Mechanism:**
- Trigger A: `above: {high_threshold}` → sets `input_boolean.{room}_lux_high` to on → Layer 3 sets mode to off
- Trigger B: `below: {low_threshold}` → sets `input_boolean.{room}_lux_high` to off → Layer 3 re-evaluates

Gap between thresholds must exceed the device feedback contribution:
`high_threshold - low_threshold > device_contribution`

**Trade-off:** adds a helper entity and more complex Layer 3 logic. Only worth it
if Options A–C genuinely don't fit the room's requirements.

---

## Lux Sensor Placement Considerations

Sensors mounted near or facing the controlled light are most susceptible to feedback.
Before debugging threshold values, check whether the sensor placement itself is the
root problem.

| Placement | Feedback risk | Notes |
|-----------|--------------|-------|
| Ceiling sensor, light directly above | High | Light shines directly onto sensor |
| Wall-mounted sensor, light on same wall | Medium | Depends on angle and reflectivity |
| mmWave/FP2 with integrated lux | Medium | Sensor lux is secondary — may not be well-shielded |
| Dedicated lux sensor, shielded from direct beam | Low | Best for gate applications |

The FP2 lux sensor in this project is integrated into a presence sensor. It measures
room ambient, not targeted illuminance — adequate for gating but susceptible to
feedback from nearby ceiling lights.

---

## InfluxDB Query Patterns

**Hourly max over 7 days (threshold calibration):**
```flux
from(bucket: "home_assistant")
  |> range(start: -7d)
  |> filter(fn: (r) => r["entity_id"] == "{entity_id}")
  |> filter(fn: (r) => r["_field"] == "value")
  |> aggregateWindow(every: 1h, fn: max, createEmpty: false)
```

**Min and max over the full range (sanity check):**
```flux
from(bucket: "home_assistant")
  |> range(start: -30d)
  |> filter(fn: (r) => r["entity_id"] == "{entity_id}")
  |> filter(fn: (r) => r["_field"] == "value")
  |> reduce(
      identity: {min: 999999.0, max: 0.0},
      fn: (r, accumulator) => ({
        min: if r._value < accumulator.min then r._value else accumulator.min,
        max: if r._value > accumulator.max then r._value else accumulator.max,
      })
    )
```

**Readings during a specific time window (e.g. only daytime hours):**
```flux
from(bucket: "home_assistant")
  |> range(start: -7d)
  |> filter(fn: (r) => r["entity_id"] == "{entity_id}")
  |> filter(fn: (r) => r["_field"] == "value")
  |> filter(fn: (r) => {
      hour = int(v: r._time) / 3600 % 24
      return hour >= 8 and hour <= 17
    })
  |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
```

---

## Slow-Decay Signal Hysteresis

A different problem from feedback oscillation — the device does NOT affect the sensor.
Instead the signal has a natural rise-and-fall curve (shower humidity, cooking temperature,
CO2 after a person leaves). A static threshold causes the automation to turn off during
the natural decay phase, even though the condition being detected is still in progress.

**Classic pattern:**
1. Shower starts → humidity rises above 60% → lights stay on (desired)
2. Shower continues → humidity peaks at 66% then slowly declines (natural steam equilibration)
3. 25 minutes in → humidity decays back below 60% → lights turn off (wrong — shower still running)

This is NOT oscillation. The device has no effect on the sensor. The problem is that
a static threshold has no memory — it can't distinguish "humidity falling because shower
ended" from "humidity falling because the room is equilibrating mid-shower".

**Diagnostic:**
- Pull HA history for the sensor during the event
- If the signal peaked and then declined naturally, and the automation fired on the
  decline, this is the slow-decay problem
- InfluxDB hourly max is insufficient here — you need the raw trace during the event

**Fix: self-referential hysteresis in the Layer 1 template**

Add a fourth branch to the template that reads the entity's current state:

```jinja2
{{ signal_condition_1
   or signal_condition_2
   or sensor_value > HIGH_THRESHOLD
   or (is_state('binary_sensor.{room}_presence', 'on')
       and sensor_value > LOW_THRESHOLD) }}
```

- **Turn-on threshold** (HIGH_THRESHOLD): must be clearly above dry baseline to avoid
  false positives. Calibrate against InfluxDB data.
- **Stay-on threshold** (LOW_THRESHOLD): lower bound that holds the entity on once activated.
  Gap between thresholds must exceed the natural decay rate over the expected event duration.
- The self-referential branch only holds `on` — it cannot turn the entity on from `off`.

**Calibration example (en-suite shower, 2026-03-23):**
- Dry baseline: 41–43% (7-day InfluxDB min)
- Shower peak: 64–66%
- Turn-on: 60% (17–18% above baseline, 4–6% below peak)
- Stay-on: 55% (14% above baseline)
- Result: gate activates when steam rises above 60%, holds until humidity falls
  below 55% — covers tail end of long showers that previously caused mid-shower lights-off

**When to use:** Any Layer 1 signal that represents an extended condition via a sensor
that rises and falls (shower/bath: humidity; cooking: temperature or CO2; gym: CO2 or
temperature). Not needed for binary sensors or sensors that don't decay during the event.

---

## Cases From This Project

| Room | Sensor | Threshold | Problem | Fix |
|------|--------|-----------|---------|-----|
| Main bathroom | FP300 integrated lux | 40 lx | Ambient 39 lx, lights on → 90 lx. 40 lx in oscillation zone. | Removed gate — interior room, always needs lights |
| Upstairs landing | Apollo MSR-2 lux | 20 lx | Cooldown always dimmed even when lux gate kept lights off during occupied (phantom dim). Not an oscillation bug — a logic gap. | Added `cooldown + lux ≥ threshold → off` before unconditional `cooldown → dim` |
| Downstairs hallway | FP2 integrated lux | 50 lx | Ambient 43 lx, lights on → 68 lx. 50 lx in oscillation zone. InfluxDB showed daytime readings 100–13,000 lx (threshold was simply wrong). | Sun gate — no feedback risk, correlates well with "don't need lights" |

---

## Relationship to Other Skills

- **`ha-4layer-presence`** — covers the lux gate architecture and where it sits in
  Layer 3. This skill covers what to do when the gate misbehaves.
- If the rapid cycling is on an **occupancy state trigger** (not numeric_state), the
  cause is sensor debounce in Layer 2 — see `ha-4layer-presence` for the
  `for: "00:00:0X"` debounce pattern on the `presence_off` trigger.
