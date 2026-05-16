# Presence Engine — Grafana Reference

Full dashboard and query reference for the presence detection observability layer.
Read this file when building, modifying, or debugging Grafana dashboards for the presence engine.

---

## Dashboard: Presence Engine

Single dashboard with 7 rows. Use Grafana's row collapse feature to keep it navigable.
All panels use the HA InfluxDB datasource unless noted.

Dashboard variables to create:
- `$room` — multi-value, values from tag `room` in `presence_fsm_transition`
- `$person` — multi-value, values from tag `person` in `presence_person_transition`
- `$timeRange` — standard Grafana time range picker

---

## Row 1 — Raw Signal Heatmap

**Purpose:** See every physical sensor signal over time. Spot flapping sensors, brief triggers,
cat activity. This is Layer 1 truth — no logic applied.

**Panel type:** State timeline
**One band per entity**, grouped by room using display name overrides.

```flux
from(bucket: "homeassistant")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] =~ /binary_sensor\..*_raw/)
  |> filter(fn: (r) => r["_field"] == "value")
  |> aggregateWindow(every: 10s, fn: last, createEmpty: false)
```

**Colour mapping:**
- `0` / `off` → light grey
- `1` / `on` → amber

**What to look for:**
- Single PIR blip, no mmWave = likely cat
- Rapid alternating on/off = sensor flapping (check zigbee signal strength)
- mmWave on, PIR never fires = person very still (valid, mmWave is better)

---

## Row 2 — Room FSM State Timeline

**Purpose:** At a glance, see every room's presence history. Gaps where occupied expected =
missed detections. Short confirmed blips = false positives.

**Panel type:** State timeline, one band per room
**Data source:** `presence_fsm_transition` events in InfluxDB

```flux
from(bucket: "homeassistant")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "presence_fsm_transition")
  |> filter(fn: (r) => r["_field"] == "to_state")
  |> filter(fn: (r) => contains(value: r["room"], set: ${room:json}))
  |> pivot(rowKey: ["_time", "room"], columnKey: ["_field"], valueColumn: "_value")
```

**Colour mapping:**
- `vacant` → #808080 (grey)
- `maybe_occupied` → #FFCC00 (yellow)
- `occupied` → #FF8C00 (orange)
- `confirmed_occupied` → #00C853 (green)
- `clearing` → #2196F3 (blue)

---

## Row 3 — Person Location Timeline

**Purpose:** Validate BLE RSSI thresholds and entry detection. See if person location
tracks correctly through the house over a day.

**Panel type:** State timeline, one band per person

```flux
from(bucket: "homeassistant")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "presence_person_transition")
  |> filter(fn: (r) => r["_field"] == "to_state")
  |> filter(fn: (r) => contains(value: r["person"], set: ${person:json}))
```

**Colour mapping:**
- `away` → #808080 (grey)
- `entering` → #FFCC00 (yellow)
- `home` → #2196F3 (blue)
- `in_room` → #00C853 (green)
- `sleeping` → #9C27B0 (purple)

Add a second panel in this row showing `location` field from the same measurement —
which room the person is modeled to be in. Useful for spotting location mismatches.

---

## Row 4 — Transition Event Log

**Purpose:** Primary debugging tool. Find the exact event causing unexpected behaviour.
Filter by room, trigger type, and time window.

**Panel type:** Logs / Table
**Columns:** `_time`, `room`, `from_state`, `to_state`, `trigger`, `signals_active`

```flux
from(bucket: "homeassistant")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "presence_fsm_transition")
  |> filter(fn: (r) => contains(value: r["room"], set: ${room:json}))
  |> pivot(rowKey: ["_time", "room", "from_state", "to_state", "trigger"], 
           columnKey: ["_field"], valueColumn: "_value")
  |> sort(columns: ["_time"], desc: true)
```

Add a dashboard variable `$trigger` with values: `pir`, `mmwave`, `ble`, `timeout`, `door`
so you can filter the log to e.g. all PIR-triggered transitions across all rooms.

**Usage pattern for debugging:**
1. Set time range to window of unexpected event
2. Filter `$room` to affected room
3. Find the transition row — read `trigger` and `signals_active`
4. Cross-reference Row 1 for the same timestamp to see raw signals

---

## Row 5 — Cat False Positive Tracker

**Purpose:** Quantify cat false positives per room per day. Track improvement as cat
exclusion rules are tightened.

A cat false positive is defined as: a `maybe_occupied` state that expires back to `vacant`
without ever advancing to `occupied`.

**Panel type:** Bar chart (count per room per day) + Table (individual events)

```flux
// Count of maybe_occupied → vacant transitions (cat events)
from(bucket: "homeassistant")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "presence_fsm_transition")
  |> filter(fn: (r) => r["from_state"] == "maybe_occupied")
  |> filter(fn: (r) => r["to_state"] == "vacant")
  |> group(columns: ["room"])
  |> aggregateWindow(every: 1d, fn: count, createEmpty: false)
```

Add a stat panel showing total cat events in the selected time range.
Add a time-of-day histogram to spot peak cat activity windows (typically early morning).

**Trend line:** if cat events per day is decreasing over weeks, exclusion rules are improving.
If a specific room has persistent high counts, review its mmWave zone configuration.

---

## Row 6 — Calibration Panel

**Purpose:** Data-driven timeout calibration. Use after 1+ week of data to set all
`input_number` timeout helpers to real observed values. Update Calibrated Values Registry
in SKILL.md with results.

**Panel 6a — Clearing timeout distribution**
How long rooms spend in `clearing` before going `vacant`. If median << your configured
timeout, you're waiting too long. If rooms sometimes skip clearing → vacant, timeout too short.

```flux
from(bucket: "homeassistant")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "presence_fsm_transition")
  |> filter(fn: (r) => r["from_state"] == "clearing" and r["to_state"] == "vacant")
  |> filter(fn: (r) => r["_field"] == "duration_ms")
  |> group(columns: ["room"])
  |> histogram(bins: linearBins(start: 0.0, width: 5000.0, count: 24))
```

**Panel 6b — Confirm timeout distribution**
How long rooms spend in `occupied` before confirming. Tune `confirm_timeout` so it's above
the 90th percentile of real walk-through durations (those should stay at `occupied`, not confirm).

```flux
from(bucket: "homeassistant")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "presence_fsm_transition")
  |> filter(fn: (r) => r["from_state"] == "occupied" and r["to_state"] == "confirmed_occupied")
  |> filter(fn: (r) => r["_field"] == "duration_ms")
  |> group(columns: ["room"])
```

**Panel 6c — maybe_occupied duration**
Distribution of time in `maybe_occupied`. This shows you whether your hold thresholds are
catching genuine occupancy or letting cat events through. Bimodal distribution = good (short
= cat, long = human). Unimodal short = everything is being treated like a cat.

---

## Row 7 — System Health

**Purpose:** Know immediately if the instrumentation pipeline itself has broken.
If these panels go red, debugging data is unreliable.

**Panel 7a — AppDaemon heartbeat**
AppDaemon should fire a `presence_heartbeat` event every 60 seconds. Alert if gap > 2 minutes.

```flux
from(bucket: "homeassistant")
  |> range(start: -5m)
  |> filter(fn: (r) => r["_measurement"] == "presence_heartbeat")
  |> count()
```
Threshold: green if count > 3, red if 0.

**Panel 7b — FSM activity rate**
Count of FSM transitions in last hour. If zero during waking hours, something is wrong.

```flux
from(bucket: "homeassistant")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "presence_fsm_transition")
  |> count()
```

**Panel 7c — Unavailable sensors**
Count of `_raw` entities currently in `unavailable` state. Any > 0 means degraded input.

Query via HA API or filter InfluxDB for `unavailable` string values in raw sensor measurements.

**Panel 7d — InfluxDB write lag**
Time since last event written. If > 5 minutes, InfluxDB integration may be broken.

---

## AppDaemon Heartbeat Setup

Add to your AppDaemon `apps.yaml` and create a `heartbeat.py` app:

```python
import hassapi as hass

class PresenceHeartbeat(hass.Hass):
    def initialize(self):
        self.run_every(self.beat, "now", 60)
    
    def beat(self, kwargs):
        self.fire_event("presence_heartbeat", source="appdaemon")
```

```yaml
# apps.yaml
presence_heartbeat:
  module: heartbeat
  class: PresenceHeartbeat
```

---

## Debugging Workflow Reference

**Unexpected automation fired:**
1. Note timestamp
2. Row 4 → filter by room + time → find transition → read `trigger`
3. Row 1 → same room + time → which raw sensors were active?
4. If PIR only → cat exclusion bug in FSM
5. If mmWave + PIR → genuine occupancy, why did automation fire unexpectedly? Check automation logic.
6. Row 3 → was the person actually expected to be in that room?

**Room stuck in occupied:**
1. Row 2 → confirm it's genuinely stuck (green band with no clearing)
2. Row 1 → any raw sensors still active? (mmWave can get stuck)
3. Row 4 → last transition — what was the trigger, did clearing ever fire?
4. Check AppDaemon logs for timer cancellation errors

**Person location wrong:**
1. Row 3 → when did location last update correctly?
2. Row 4 → filter by `trigger=ble` — is BLE firing at all?
3. Check BLE RSSI thresholds in Calibrated Values Registry — may need lowering
4. Cross-reference Row 2 — does room FSM agree with person location?

**Cat events increasing:**
1. Row 5 → which room, what time of day
2. Row 1 → same room, same time → confirm PIR only, no mmWave
3. Review mmWave zone height configuration for that room
4. Consider raising PIR hold timer to reduce sensitivity

