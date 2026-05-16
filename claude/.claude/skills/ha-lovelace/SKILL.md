---
name: ha-lovelace
description: >
  Use this skill when working on Home Assistant Lovelace dashboards. Triggers include:
  "dashboard", "card", "button-card", "tile card", "lovelace", "scene buttons",
  "active scene indicator", "dashboard layout", "apexcharts", "card-mod",
  "MDI icon", "stepline", "logbook card", "sonos card", "python_transform",
  "config_hash", or any request to build, edit, or debug HA frontend UI.
  Also trigger when the user asks why a card isn't highlighting, why an icon
  is missing, or why a dashboard edit failed. Use proactively whenever presence
  or scene automation work includes a frontend component.
---

# Home Assistant Lovelace Dashboard Skill

Patterns, constraints, and pitfalls for building HA dashboards — derived from
real implementation, not documentation. Every entry here was discovered the hard way.

---

## Card Type Selection

### When to use `custom:button-card`

Use button-card when:
- Buttons need to **visually reflect state from a different entity** than the one being activated
- You need **state-independent styling** — tile cards suppress `--tile-color` when entity state is "off"
- You need JS template expressions (`[[[...]]]`) for dynamic background/border/color

Key properties:
```json
{
  "type": "custom:button-card",
  "entity": "input_select.downstairs_active_scene",
  "name": "Morning",
  "icon": "mdi:weather-sunset-up",
  "show_state": false,
  "tap_action": {
    "action": "call-service",
    "service": "script.turn_on",
    "target": {"entity_id": "script.downstairs_morning"}
  },
  "styles": {
    "card": [
      {"background-color": "[[[return states['input_select.downstairs_active_scene'].state === 'morning' ? 'rgba(245, 158, 11, 0.2)' : 'var(--card-background-color)']]]"},
      {"border": "[[[return states['input_select.downstairs_active_scene'].state === 'morning' ? '2px solid #f59e0b' : '2px solid transparent']]]"},
      {"border-radius": "12px"}
    ],
    "icon": [{"color": "var(--primary-text-color)"}],
    "name": [{"font-size": "12px"}, {"font-weight": "500"}]
  }
}
```

**Critical:** `styles` uses **arrays of single-property objects**, not a flat dict.
Each CSS property gets its own list item. Putting multiple properties in one object
will silently produce unpredictable results.

**Icon color:** Always use `var(--primary-text-color)` for icon color on highlighted cards.
Never match icon color to the active highlight color — amber icon on amber background is invisible.

**Entity decoupling:** `entity` is the state-reading entity (for JS templates). `tap_action`
calls the actual service. These can be completely different entities — this is intentional.

### When NOT to use tile cards with card-mod

`--tile-color` is suppressed by tile cards when the underlying entity state is "off".
Scripts are always "off" when idle. If you need highlighting on script-backed buttons,
tile cards will not work regardless of card-mod configuration.

Use tile cards only when:
- The entity has native on/off/unavailable state and you want its default styling
- You don't need custom active state highlighting
- `tap_action: more-info` is sufficient UX

### `input_select` tile cards

`select-select` tile feature only works for the `select` integration domain.
For `input_select` tiles, use `tap_action: {action: more-info}` to open a picker dialog.
There is no inline dropdown control for `input_select` on tile cards.

---

## Scene Active Indicator Pattern

When multiple scene scripts need to show which one is "active":

1. **Create a helper:** `input_select.{zone}_active_scene` with options matching your scenes
   (e.g. `none / morning / relaxed / dinner / movie / wind_down`)

2. **Create a tracker automation** that watches all scene scripts going to state `on`,
   then sets the `input_select` to the matching option:
   ```yaml
   trigger:
     - trigger: state
       entity_id: script.downstairs_morning
       to: "on"
     - trigger: state
       entity_id: script.downstairs_relaxed
       to: "on"
   action:
     - choose:
       - conditions:
           - condition: template
             value_template: "{{ trigger.entity_id == 'script.downstairs_morning' }}"
         sequence:
           - action: input_select.select_option
             target:
               entity_id: input_select.downstairs_active_scene
             data:
               option: morning
   ```

3. **Point button-card `entity`** at the `input_select`, tap_action at the script.
   The JS template compares `states['input_select.downstairs_active_scene'].state`
   to the scene name for each button.

**Why external tracker, not in-script:** Scripts do not need to be modified.
The tracker fires on the script state transition to "on" — it's a side-channel observer.

---

## MDI Icons

**Silent failure:** Invalid MDI icon names render as a blank space with no error message,
no console warning, and no indication the name is wrong.

**Always verify icons in the HA icon browser before using them.**

Common mistakes:
- `mdi:weather-sunrise` — does not exist → use `mdi:weather-sunset-up`
- `mdi:home-lightning-bolt` — check spelling carefully
- Icon names change between MDI versions; HA's bundled version may lag

---

## ApexCharts — State History Stepline

Standard pattern for visualising presence/occupancy/mode state over time:

```yaml
type: custom:apexcharts-card
graph_span: 3h
update_interval: 30s
header:
  show: true
  title: Transition History
chart_type: line
apex_config:
  chart:
    type: line
  stroke:
    curve: stepline
    width: 2
  xaxis:
    type: datetime
  yaxis:
    min: 0
    max: 3
    tickAmount: 3
    labels:
      show: false
series:
  - entity: input_select.landing_occupancy_state
    name: "Occ. State"
    color: "#3b82f6"
    transform: "return {'idle': 0, 'occupied': 1, 'cooldown': 2}[x] ?? 0"
  - entity: binary_sensor.upstairs_hallway_presence
    name: "Presence"
    color: "#22c55e"
    transform: "return x === 'on' ? 3 : 0"
  - entity: input_select.landing_lighting_mode
    name: "Mode"
    color: "#f59e0b"
    transform: "return {'off': 0, 'dim': 1, 'normal': 2, 'night': 3}[x] ?? 0"
```

**`apex_config` does not evaluate string functions.**
`apex_config` is passed directly to the ApexCharts library. If a callback (e.g.
`yaxis.labels.formatter`) is a string instead of a real JS function, ApexCharts
fails silently and shows a perpetual loading spinner. The series `transform`
property IS safe as a string — apexcharts-card evaluates it before passing data
to ApexCharts. Never put function strings inside `apex_config`.

**Numeric state mapping:** Map discrete states to integers for the y-axis.
Keep yaxis min/max tight around your range. 0 = off/idle is conventional.

---

## Dashboard Transforms — `python_transform`

`python_transform` in `ha_config_set_dashboard` is the right approach for surgical edits
(replacing sections, appending views) without replacing the entire dashboard config.

Rules:
- Always pass `config_hash` — fetch the dashboard immediately before transforming to get a fresh hash
- **Forbids negative numbers** — the restricted AST validator rejects unary negation (`USub`).
  Negative literals like `-0.5` fail with "Forbidden node type: USub". If the config
  requires negative numbers, use full `config` replacement instead.

---

## Inline JS Dashboard Resources

HA serves inline JS resources without `Content-Type: application/javascript; charset=utf-8`.
Browsers default to ISO-8859-1, corrupting every multi-byte UTF-8 character.

**Rule: use HTML entities for all non-ASCII characters in inline JS card code.**
- `&#x2192;` not `→`
- `&#x2014;` not `—`
- Never paste literal emoji into inline JS

---

## Diagnostic Patterns

### `result: []` from `ha_call_service` is normal

`light.turn_on` and similar services return no data. An empty result array means the
service was dispatched — not that it failed. Light state changes are asynchronous.
To confirm a command was received, check `ha_get_state` after a moment.

### `last_changed` as a diagnostic

`last_changed` only updates when state actually changes. If a light is already at
the target brightness/colour_temp, `last_changed` will not move even if the
service was called. This is not evidence the command failed — it means the light
was already correct. Check `last_updated` or look at the floor lamp / other lights
that were not already at the target value.

### Script trace timing

Scripts completing in ~25ms is normal — HA dispatches service calls fire-and-forget.
A 25ms trace with `execution: finished` does not indicate the lights responded.
Check `ha_get_state` on the light entity, not the script trace.

---

## Dashboard Structure for Presence/Lighting Stacks

Standard per-room diagnostic view structure (sections layout, max_columns: 2):

```
Section: Layer 2 — Occupancy
  2-col grid: occupancy_state tile | cooldown timer tile

Section: Layer 1 — Sensors
  2-col grid: fused presence tile | raw sensor tiles

Section: Layer 3 — Lighting Mode
  3-col grid: lighting_mode tile | lux sensor | sleep_mode

Section: Layer 4 — Lights
  1 tile: the room light

Section: Transition History
  apexcharts stepline (3h, stepline curve, 3 series: occ state, presence, mode)

Section: Event Log
  logbook card (1h, scoped to all relevant entities)
```

---

## Fully Kiosk Browser — Wall Panel Pattern

When a tablet is running Fully Kiosk Browser with the HA integration installed, it exposes
a rich set of entities that enable proper wall panel automation. Always prefer Fully Kiosk
controls over cloud TTS or companion app notifications for wall-mounted devices.

**Key entities (prefix: `{device_slug}`):**

| Entity | Use |
|--------|-----|
| `notify.{device}_text_to_speech` | Speak directly through tablet speaker — no cloud roundtrip |
| `notify.{device}_overlay_message` | Display a text overlay on screen |
| `switch.{device}_screen` | Wake (on) or sleep (off) the screen |
| `switch.{device}_screensaver` | Dismiss (off) or enable (on) the screensaver |
| `number.{device}_screen_brightness` | Set screen brightness (0–255) |
| `media_player.{device}` | Volume control + media playback via `media_player.volume_set` |
| `sensor.{device}_battery` | Battery level — use for charging automation |
| `binary_sensor.{device}_plugged_in` | Charging state |
| `sensor.{device}_current_page` | Confirms which dashboard URL is being shown |

**Alarm / wake sequence pattern:**
```yaml
- service: switch.turn_off          # dismiss screensaver first
  target: {entity_id: switch.{device}_screensaver}
- service: switch.turn_on           # wake screen
  target: {entity_id: switch.{device}_screen}
- delay: "00:00:08"                 # let screen settle
- service: media_player.volume_set  # ensure audible volume
  target: {entity_id: media_player.{device}}
  data: {volume_level: 0.8}
- service: notify.{device}_text_to_speech
  data: {message: "Your message here"}
- service: notify.{device}_overlay_message
  data: {message: "Visible text on screen"}
```

**Charging automation pattern** (power socket managed by HA):
- Trigger: battery below threshold → turn socket ON; battery above threshold → turn socket OFF
- Always use `mode: single` (not restart) — actions are instant, no benefit to restart
- Always add `homeassistant: start` trigger with both threshold checks as choose branches
  so the automation recovers correctly after HA restarts mid-charge-cycle
- Recommended window: 20–95% (avoids deep discharge + prevents constant 100% which degrades battery)

**Calendar card for school schedule on wall panel:**
```yaml
type: calendar
entities:
  - calendar.{schedule_entity}
initial_view: listWeek   # list view shows upcoming lessons cleanly — better than month grid for wall panels
```

---

## Common Card Configurations

### Logbook card (scoped)

```yaml
type: logbook
title: Event Log
hours_to_show: 1
entities:
  - input_select.landing_occupancy_state
  - binary_sensor.upstairs_hallway_presence
  - input_select.landing_lighting_mode
  - light.hallway_upstairs_light
```

### Timer tile

```yaml
type: tile
entity: timer.landing_occupancy_cooldown
name: Cooldown Timer
tap_action:
  action: more-info
```

### Input_select tile (no inline control)

```yaml
type: tile
entity: input_select.landing_occupancy_state
name: Occupancy State
tap_action:
  action: more-info
```
