---
name: unifi-network
description: >
  Reference skill for Aaron's home network — zone IDs, VLAN assignments, subnet map,
  key hosts, and firewall policy design intent. Load this skill at the start of any
  UniFi firewall, VLAN, or network configuration session so zone names and IDs are
  immediately available without a discovery pass. Triggers include: "what zone is X in",
  "what's the subnet for", "which VLAN", "zone IDs", "network reference", or any
  UniFi session where knowing the network layout would avoid repeated MCP lookups.
  Always pair with the unifi-zbf skill for procedural guidance.
---

# Aaron's Home Network — Reference Card

**Controller:** UDM-Pro-Max at `192.168.100.1`  
**API type:** local  
**Default site:** `default`  
**MCP server:** `http://192.168.30.28:3000/sse` (v0.2.5+)

---

## Zone Map

Both ID formats are included. Use **Integration UUID** for zone CRUD tools.
Use **ObjectId** for firewall policy tools (or just pass the zone name — tools resolve it).

| Zone | Type | Integration UUID | v2 ObjectId |
|------|------|-----------------|-------------|
| Internal | SYSTEM | `a31217f8-8e0b-4b40-b338-30de0f1fac72` | `6842f4b49bb16a6d2f2e4be9` |
| External | SYSTEM | `d78b40bc-b177-4178-9557-8a459472e23a` | `6842f4b49bb16a6d2f2e4bea` |
| Gateway | SYSTEM | `f9cc8d3e-eb31-47d8-a66b-96c2cb369939` | `6842f4b49bb16a6d2f2e4beb` |
| Vpn | SYSTEM | `bd67f169-3524-43e8-9b88-effa21372dc9` | `6842f4b49bb16a6d2f2e4bec` |
| Hotspot | SYSTEM | `e980cb8b-a59a-4089-afbe-3cc703828bf0` | `6842f4b49bb16a6d2f2e4bed` |
| Dmz | SYSTEM | `4a9e2860-d696-43b7-9ef9-3edefb2c1553` | `6842f4b49bb16a6d2f2e4bee` |
| IoT | USER | `908f2515-d0ea-4b69-8a3e-bfccf34e933c` | `69d013f90e6d286995871e1b` |
| Camera | USER | `01ea5be2-9339-454f-a7a7-3195b70074bc` | `69d013f90e6d286995871e1e` |
| Kids | USER | `238604e8-1ab2-472b-bc58-7f2b6eff5488` | `6a0616f01c46c24bb41370d5` |
| Infrastructure | USER | `6229119c-42ad-4801-bc7c-0fb75ab3e2cd` | `6a0726ec1c46c24bb4164af4` |
| Management | USER | *(created in session — run list_firewall_zones_v2 to get IDs)* | — |

> **Note:** Zone IDs were verified 2026-05-16. Re-verify with `list_firewall_zones_v2`
> if anything looks wrong — UUIDs are stable but ObjectIds can change after controller reset.

---

## VLAN & Network Map

**Two network ID formats exist — use the right one for the tool:**
- **MongoDB ObjectId** (24-char hex) — from `list_vlans`, `list_firewall_zones_v2`. Use with `assign_network_to_zone` and policy tools.
- **Integration v1 UUID** (hyphenated) — from `list_firewall_zones` → `networkIds` or `get_zone_networks` → `network_id`. Required for `unassign_network_from_zone`.

| Network | VLAN | Subnet | MongoDB ObjectId | Integration v1 UUID | Zone |
|---------|------|--------|-----------------|---------------------|------|
| Default | — | 192.168.100.0/24 | `68382d05ade22f0861f5456c` | `b7b0b07c-91db-4dc2-aba4-f1a53d3b8d46` | Internal |
| Trusted | 10 | 192.168.10.0/24 | `6838627c663ef63a10f23267` | `128eba3d-adc7-4262-8707-4622ca0373db` | Internal |
| Infrastructure | 30 | 192.168.30.0/24 | `683862e2663ef63a10f23270` | `4f336d9a-227c-4fb0-b13b-99af88c6798a` | Infrastructure |
| IoT Devices | 20 | 192.168.20.0/24 | `68386330663ef63a10f23273` | `db2a7318-22df-478e-8d5d-3508a7a0af45` | IoT |
| Camera | 70 | 192.168.70.0/24 | `6838a838663ef63a10f233c4` | `bc7425a6-fc0e-4b5a-9858-94186e8bb554` | Camera |
| Management | 254 | 192.168.254.0/24 | `6840ab528fea507c24d0e5a8` | `72a137b8-3df3-4922-b36e-0be366340967` | Management (pending) |
| VPN-L2TP (VLAN) | 40 | 192.168.40.0/24 | `687c96eebed99016790f35cc` | `c601feb0-4fc3-4dd1-8583-6e820d5398b3` | Internal |
| VPN-L2TP (remote) | — | 192.168.3.0/24 | `687cbf64bed99016790f53d4` | *(Vpn zone, not moved)* | Vpn |
| Kids | 50 | 192.168.50.0/24 | `6a0616e41c46c24bb41370b1` | `df37945a-f3bc-43d4-830d-8efe8dba9ca9` | Kids |
| v6-lab | 230 | 192.168.4.0/24 | `68b401daf687c35bc9062f3b` | `b34dfb5a-02ad-4155-a7b3-207844bffcfa` | Internal |
| Internet 1 | — | WAN | `68382d05ade22f0861f5456a` | `c7205241-c38b-4b06-95c6-db7f14aa7e76` | External |
| Internet 2 | — | WAN | `68382d05ade22f0861f5456b` | `5b460f51-45c2-4801-a40b-a5c0bc19be6b` | External |
| KPN Direct | — | WAN | `69d547597fcb3cddfbae4885` | `3a4f5be6-2873-4ded-af33-7f1638d028cc` | External |

> v1 UUIDs verified 2026-05-16 via `get_zone_networks`. Required for `unassign_network_from_zone` — MongoDB ObjectIds silently fail that tool.

---

## Key Hosts

| Host | IP | VLAN | Role |
|------|----|------|------|
| UDM-Pro-Max | 192.168.100.1 | Default | Router / UniFi controller |
| docker-01 | 192.168.30.11 | Infrastructure | Frigate NVR, Pi-hole primary |
| docker-02 | 192.168.30.119 | Infrastructure | Metrics (node-red, unifi-poller) |
| NAS | 192.168.30.10 | Infrastructure | InfluxDB, Grafana, MQTT |
| Proxmox | 192.168.30.6 | Infrastructure | Virtualisation host |
| Pi-hole | 192.168.30.12 | Infrastructure | DNS resolver (used by all VLANs) |
| NPM | 192.168.30.13 | Infrastructure | NGINX Proxy Manager |
| Home Assistant | 192.168.30.5 | Infrastructure | HA instance (MCP on port 8086) |
| Grafana | 192.168.30.25 | Infrastructure | Dashboards (port 8000) |
| InfluxDB | 192.168.30.26 | Infrastructure | Time series (port 3000 for MCP) |
| UniFi MCP | 192.168.30.28 | Infrastructure | UniFi MCP server (port 3000 SSE) |
| Frigate NVR | 192.168.30.15 | Infrastructure | Camera NVR (docker macvlan) |
| SLZB-06P10 | 192.168.30.40 | Infrastructure | Zigbee/Thread coordinator (TCP 6638) |
| Camera — Front | 192.168.70.3 | Camera | Reolink wired (MAC ec:71:db:03:b0:7b) |
| Camera — Back | 192.168.70.5 | Camera | Reolink wired (MAC ec:71:db:40:5a:4d) |
| Camera — Hallway | 192.168.70.112 | Camera | WiFi, fixed IP, AP-locked downstairs (MAC 0c:91:60:69:86:c4) |
| Camera — Snug | 192.168.70.177 | Camera | WiFi, fixed IP, AP-locked downstairs (MAC 28:7b:11:fe:44:e6) |

DNS for most VLANs: **192.168.30.12** (Pi-hole)  
Kids VLAN DNS: **185.228.168.9 / 185.228.169.9** (CleanBrowsing family filter)

---

## Zone Security Design Intent

| Zone | Trust Level | Design Intent |
|------|-------------|---------------|
| **Internal** | Trusted | Full LAN — Default network, Trusted VLAN 10, VPN client VLAN 40, v6-lab |
| **External** | Untrusted | WAN interfaces — no inbound except port forwards + return traffic |
| **Gateway** | System | Router itself — allow all outbound from gateway; all inbound from any zone |
| **Vpn** | Trusted | VPN tunnel endpoints — VPN users get Internal-equivalent access |
| **Infrastructure** | Service | Servers and services — reachable by Trusted/Kids on specific ports only |
| **Management** | Restricted | Network management plane — reachable by Internal + Vpn only; very locked down |
| **IoT** | Untrusted | IoT devices — internet allowed (with port blocks), DNS via Pi-hole, no lateral movement |
| **Camera** | Isolated | CCTV cameras — internet blocked, can only reach Frigate NVR in Internal |
| **Kids** | Filtered | Kids devices — internet with CleanBrowsing DNS, specific services (JellyFin, HA, NPM) |
| **Dmz** | Isolated | DMZ — can reach External; blocked from Internal/IoT/Camera/Kids |

---

## User-Defined Policies Summary

Policies verified 2026-05-16. Predefined (UniFi default) policies omitted.

### Internal zone outbound
- `Internal → Infrastructure` : Allow Trusted → NPM, HA, NAS (specific ports)
- `Internal → Infrastructure` : Allow Infrastructure → Internet (typo in name — actually Internal)
- `Internal → IoT` : Allow Infrastructure→IoT, Allow Internal→Matter, Allow Thread Border Routers
- `Internal → Internal` : Internal DNS, Allow RA to IoT
- `Internal → Kids` : Allow Trusted → Kids
- `Internal → Camera` : Allow Frigate → Camera

### IoT zone
- `IoT → External` : Block SSH, Allow Internet, Allow ICMPv6, Block external DNS (IPv4+v6)
- `IoT → Gateway` : Allow IoT → NTP
- `IoT → Internal` : Allow IoT → DNS (Pi-hole), Allow IoT → Infrastructure

### Camera zone
- `Camera → Internal` : Allow Cameras → Frigate NVR
- `Camera → External` : Block Camera SSH outbound, Block Camera → Internet

### Kids zone
- `Kids → Infrastructure` : Allow DNS, JellyFin, HA, NPM
- `Kids → External` : Block SSH, Allow Internet, Block external DNS
- `Kids → Gateway` : Allow Kids NTP

---

## Open Items / Known Issues (as of 2026-05-16)

- **Infrastructure zone**: VLAN 30 being moved from Internal → Infrastructure (in progress)
- **Management zone**: Being created; VLAN 254 being moved from Internal → Management (in progress)
- **IoT → Internal duplicate return rule**: "Allow Infrastructure → IoT (Return)" appears twice — harmless but worth cleanup
- **Naming typo**: "Allow Inffrastructure → Internet" policy has double-f in name
- **Management zone policies**: Need to be created after zone creation — inbound: Internal+Vpn allowed; outbound: External+Gateway+Internal+IoT+Camera allowed; Infrastructure: blocked
