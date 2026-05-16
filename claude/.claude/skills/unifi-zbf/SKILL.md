---
name: unifi-zbf
description: >
  Use this skill when managing UniFi Zone-Based Firewall (ZBF) — creating, reading,
  updating, or deleting zone-to-zone firewall policies, managing zones, or assigning
  networks to zones. Triggers include: "firewall policy", "zone policy", "ZBF",
  "allow traffic between", "block traffic from", "zone to zone", "create firewall rule",
  "assign network to zone", "firewall zones", or any request to change inter-VLAN
  security policy via the UniFi ZBF system. Also trigger proactively when the user
  asks what traffic is allowed between two VLANs or zones, or when debugging connectivity
  issues between VLANs.
---

# UniFi Zone-Based Firewall (ZBF) Management

## Zone ID Warning — Read First

UniFi zones have two IDs. Always call `list_firewall_zones_v2` at session start — it returns both.

| ID Type | Format | Used By |
|---------|--------|---------|
| **Integration UUID** | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | Zone CRUD tools (`create_firewall_zone`, `assign_network_to_zone`, `unassign_network_from_zone`, `delete_firewall_zone`, `get_zone_networks`) |
| **v2 ObjectId** | 24-char hex, e.g. `6842f4b49bb16a6d2f2e4be9` | Policy tools (`create_firewall_policy`, `update_firewall_policy`, `list_firewall_policies`) |

Pass zone names to policy tools — they resolve automatically. Pass the Integration UUID to zone CRUD tools.

---

## Local API Requirement

**All ZBF tools require `UNIFI_API_TYPE=local`.** Cloud API does not support ZBF.
Verify with `health_check` — `api_type` must be `"local"`.

---

## Tool Reference

### Reading

| Tool | Purpose |
|------|---------|
| `list_firewall_zones` | List all zones with integration UUIDs and network assignments |
| `list_firewall_zones_v2` | List all zones with **both** UUIDs and ObjectIds — use this first |
| `list_firewall_policies` | List all policies (188+ typical); filter by `source_zone_id` or `destination_zone_id` |
| `get_firewall_policy` | Get a single policy by ID |
| `get_zone_networks` | Get networks assigned to a specific zone |

### Zone Management

| Tool | Purpose | Requires |
|------|---------|---------|
| `create_firewall_zone` | Create a new zone | `confirm: true` |
| `update_firewall_zone` | Rename a zone | `confirm: true` |
| `delete_firewall_zone` | Delete a zone | `confirm: true` |
| `assign_network_to_zone` | Add a network to a zone | `confirm: true` |
| `unassign_network_from_zone` | Remove a network from a zone | `confirm: true` |

### Policy Management

| Tool | Purpose | Requires |
|------|---------|---------|
| `create_firewall_policy` | Create a zone-to-zone policy | `confirm: true` |
| `update_firewall_policy` | Modify an existing policy | `confirm: true` |
| `delete_firewall_policy` | Remove a policy | `confirm: true` |

---

## Standard Workflows

### Workflow 1: Read current ZBF state

```
1. health_check                    → verify api_type=local
2. list_firewall_zones_v2          → get zone name↔ID mapping (save for the session)
3. list_firewall_policies(site_id) → get all policies (large response — use jq/python to parse)
```

To filter to a specific zone pair:
```
list_firewall_policies(site_id, source_zone_id="<ObjectId>", destination_zone_id="<ObjectId>")
```

### Workflow 2: Create a zone-to-zone policy

```
1. list_firewall_zones_v2          → confirm zone ObjectIds
2. create_firewall_policy(
     site_id, name, action,
     source_zone_id="<name or ObjectId>",   # tool resolves either form
     destination_zone_id="<name or ObjectId>",
     dry_run=True                           # preview first
   )
3. Review dry_run output
4. create_firewall_policy(..., dry_run=False, confirm=True)
```

### Workflow 3: Move a network between zones

The correct tool depends on what type of zone the network is currently in.

**Case A — moving FROM a system zone (Internal, External, Vpn, Hotspot, Dmz, Gateway):**

```
# Do NOT call unassign_network_from_zone — the API blocks it on system zones (422).
# Just assign to the target. UniFi auto-removes from the system zone.

1. assign_network_to_zone(site_id, zone_id=<target_uuid>, network_id=<network_v1_uuid>, confirm=True)
2. list_firewall_zones_v2          → verify the network moved
```

To get the network's v1 UUID: call `get_zone_networks(site_id, zone_id=<current_zone_uuid>)` and use the `network_id` field in the result.

**Case B — moving FROM a user-defined zone (IoT, Camera, Kids, Infrastructure, etc.):**

```
1. get_zone_networks(site_id, zone_id=<source_zone_uuid>)
   → note the network_id value for the network (this is the v1 UUID you need)
2. unassign_network_from_zone(site_id, zone_id=<source_uuid>, network_id=<v1_uuid>, confirm=True)
   → network moves back to Internal zone automatically
3. If moving to another user zone (not Internal):
   assign_network_to_zone(site_id, zone_id=<target_uuid>, network_id=<v1_uuid>, confirm=True)
4. list_firewall_zones_v2          → verify
```

**Why `get_zone_networks` first?** The network IDs in zone responses are v1 UUIDs, not the MongoDB ObjectIds that `list_vlans` returns. `unassign_network_from_zone` requires the v1 UUID — passing a MongoDB ObjectId will fail silently with "not assigned to zone".

### Workflow 4: Create a new zone with policies

```
1. create_firewall_zone(site_id, name, confirm=True)
   → note the returned id (integration UUID)
2. assign_network_to_zone(site_id, zone_id=<new_uuid>, network_id=..., confirm=True)
3. list_firewall_zones_v2          → get the new zone's ObjectId for policy creation
4. create_firewall_policy(...)     → create inbound policies (what can reach this zone)
5. create_firewall_policy(...)     → create outbound policies (what this zone can reach)
```

UniFi auto-generates a "Block All Traffic" predefined policy for every zone pair when a new
zone is created. User-defined policies layer on top of these defaults.

---

## Policy Parameters

### Action
- `ALLOW` — permit traffic
- `BLOCK` — deny traffic

### Matching targets (source/destination)
- `ANY` — match all (default)
- `IP` — specific IPs or CIDRs (set `source_ips` / `destination_ips`)
- `NETWORK` — a specific VLAN (set `source_network_ids` / `destination_network_ids`)
- `CLIENT` — specific MACs (set `source_client_macs` / `destination_client_macs`)

### Protocol
- `all` (default), `tcp`, `udp`, `tcp_udp`, `icmpv6`

### Port matching
- `source_port` / `destination_port` — single port `"80"` or range `"8000-8100"`
- `source_port_group_id` / `destination_port_group_id` — reference a firewall port group
- Implies `SPECIFIC` or `OBJECT` port matching type automatically

---

## Policy Naming Convention

Use clear directional names:
- `Allow <Source> -> <Destination>` for user-defined allow rules
- `Block <Source> -> <Destination>` for explicit blocks
- Match the zone and service name: `Allow IoT -> DNS`, `Block Camera -> Internet`

---

## Common Patterns

### Allow zone A to reach specific service in zone B (all other traffic blocked)
```
# Predefined "Block All" already exists — just add the allow on top
create_firewall_policy(
  name="Allow Trusted -> HA",
  action="ALLOW",
  source_zone_id="Internal",
  destination_zone_id="Infrastructure",
  destination_port="8123",
  protocol="tcp",
  confirm=True
)
```

### Block specific outbound traffic (SSH, external DNS)
```
create_firewall_policy(
  name="Block IoT -> SSH Outbound",
  action="BLOCK",
  source_zone_id="IoT",
  destination_zone_id="External",
  destination_port="22",
  protocol="tcp",
  confirm=True
)
```

### Allow internet access but block specific ports
Create the block rules first (they evaluate before the broad allow):
```
# 1. Block SSH
create_firewall_policy(name="Block IoT -> SSH", action="BLOCK", destination_port="22", ...)
# 2. Block external DNS
create_firewall_policy(name="Block IoT -> Ext DNS", action="BLOCK", destination_port="53", ...)
# 3. Allow internet
create_firewall_policy(name="Allow IoT -> Internet", action="ALLOW", ...)
```

---

## Known Limitations

- **`unassign_network_from_zone` cannot operate on system zones** (Internal, External, Vpn, Hotspot, Dmz, Gateway) — the UniFi API returns 422 `update-forbidden`. Use `assign_network_to_zone` on the target user zone instead (Case A above).
- **`unassign_network_from_zone` requires v1 UUIDs for network_id** — MongoDB ObjectIds (from `list_vlans` or `list_firewall_zones_v2`) silently fail. Always get the v1 UUID from `get_zone_networks` first.
- **`create_firewall_policy` with `destination_zone=External` or `destination_zone=Gateway` fails** with `FirewallPolicyCreateRespondTrafficPolicyNotAllowed` when `create_allow_respond=true` (the default). These system zones already have predefined respond-traffic rules. Fix: pass `create_allow_respond=false` for any policy targeting External or Gateway as destination.
- `get_zone_statistics` — does NOT exist in the UniFi API. Raises `NotImplementedError`.
- Legacy ZBF matrix endpoints (`get_zbf_matrix`, `get_zone_policies`, etc.) — do not exist in UniFi API v10.x.
- Application blocking by zone (`block_application_by_zone`) — endpoint does not exist.
- Zone assignment is L3 only — moving a network between zones does NOT affect trunk port VLAN membership. Trunking is separate.
- A network should be in exactly ONE zone. Being in two zones causes ambiguous policy evaluation.

---

## Safety Rules

1. Always `dry_run=True` first on any mutating policy operation — review the payload before commit
2. When moving from a user zone (Case B), do unassign + assign back-to-back — the brief "Block All" gap can disrupt traffic. When moving from a system zone (Case A), there is no gap — the assign is atomic.
3. Verify with `list_firewall_zones_v2` after every zone change to confirm the network_ids updated
4. Never delete a zone without first reviewing all policies that reference it — deleting a zone with active policies may leave orphaned rules
