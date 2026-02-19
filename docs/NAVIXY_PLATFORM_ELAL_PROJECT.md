# Navixy Platform – ELAL Project: System Documentation

**Project:** Navixy Live Map – BLE asset tracking for airport GSE  
**Purpose:** Read Navixy + Teltonika (via broker) into a dynamic web map and SQL Server database.  
**Version:** 001 (drop-ready)  
**Branches:** `main` (current); `Eyebecon-As-an-Asset` (legacy, fully merged into main)

This document is the **combined reference** for all system documentation. Each section points to the dedicated MD file(s) and summarizes database schema, logic, and process.

---

## 1. Table of Contents (All Documentation)

| # | Document | Description |
|---|----------|-------------|
| 1 | [README.md](../README.md) | Purpose, architecture diagram, quick start, ports, doc index |
| 2 | [ARCHITECTURE.md](../ARCHITECTURE.md) | Data flow: Navixy + Broker → Map; components (trackers, beacons, broker, DB) |
| 3 | [BUSINESS_LOGIC.md](../BUSINESS_LOGIC.md) | 60-second pairing rule, BLE position state machine, when position updates |
| 4 | [SETUP_GUIDE.md](../SETUP_GUIDE.md) | Prerequisites, clone, venv, database setup, start services |
| 5 | [MAINTENANCE.md](../MAINTENANCE.md) | One-command start, ports, manual start, env/config, recovery, external access |
| 6 | [TELTONIKA_CONFIG.md](../TELTONIKA_CONFIG.md) | FMC650/FMC003 config: dual server, BLE Advanced parsing, EYE beacon settings |
| 7 | [docs/SQL_BLE_DATA_SPEC.md](SQL_BLE_DATA_SPEC.md) | BLE_Positions/BLE_Definitions columns; vw_BLE_Diagnostics; import from CSV |
| 8 | [docs/EYEBECON_BRANCH_SYNC.md](EYEBECON_BRANCH_SYNC.md) | Branch vs main: single source, no duplication; broker/map/DB mapping |
| 9 | [docs/CLOUDFLARE_TUNNEL_SETUP.md](CLOUDFLARE_TUNNEL_SETUP.md) | Named tunnel, fix permissions, restart service, DNS |
| 10 | [SERVER_DEPLOYMENT_GUIDE.md](../SERVER_DEPLOYMENT_GUIDE.md) | Full server deploy, DB schema, services, branch reference |
| 11 | [SERVICE_ARCHITECTURE_GUIDE.md](../SERVICE_ARCHITECTURE_GUIDE.md) | Services layout, tunnel, API, map |
| 12 | [SERVICE_TROUBLESHOOTING.md](../SERVICE_TROUBLESHOOTING.md) | Tunnel/API/map troubleshooting |
| 13 | [CLOUDFLARE_RATE_LIMIT_ISSUE.md](../CLOUDFLARE_RATE_LIMIT_ISSUE.md) | Quick tunnel 429; use named tunnel instead |
| 14 | [scripts/BEACON_DATA_REFERENCE.md](../scripts/BEACON_DATA_REFERENCE.md) | Seed data reference; run seed script |
| 15 | [REMOTE_SERVER_INSTALL/README.md](../REMOTE_SERVER_INSTALL/README.md) | Remote install notes |
| 16 | [service/README_SERVICE.md](../service/README_SERVICE.md) | Service scripts overview |

---

## 2. Real Process: Data Flow (Navixy + Teltonika → Map + DB)

```
1. Teltonika devices (FMC650/FMC003) send CODEC8 data to:
   - Navixy (cloud) – primary
   - Local broker (TCP 15027) – duplicate

2. Broker (teltonika_broker.py):
   - Listens TCP 15027, parses CODEC8, extracts BLE beacons (element 385, etc.)
   - Applies 60-second pairing logic (position update only after 60s same tracker)
   - Stores/updates BLE positions in memory and (optional) SQL Server
   - Serves HTTP :8768/data with ble_positions (and rows for trackers)

3. Map (index.html):
   - Data sources: Motorized GSE (8767 Navixy), Direct (8768 broker), Both
   - In Both mode: broker is source of truth for BLE (battery, last_update); Navixy only fills position when broker has none
   - Calls /data, gets ble_positions, renders beacons with updateBeaconMarkersFromSQL()
   - Popup shows: Battery, Last saw, BLE position info (from broker or DB)

4. Database (SQL Server 2Plus_AssetTracking):
   - BLE_Positions: current position, battery_percent, last_update, last_tracker_*
   - BLE_Definitions: name, category, ble_type per MAC
   - vw_BLE_Diagnostics: optional view (from BLE_Scans); broker enriches /data from it when battery/last_update missing
   - Broker loads BLE_Positions at startup; merges vw_BLE_Diagnostics when building /data
```

---

## 3. Database Schema (Implemented in setup_database.py)

| Table / View | Purpose |
|--------------|---------|
| **BLE_Positions** | One row per beacon: mac, lat, lng, last_update, battery_percent, last_tracker_id/label, is_paired, pairing_*, name, category, ble_type, serial_number |
| **BLE_Definitions** | mac, name, category, ble_type, serial_number, asset_id, notes |
| **BLE_Movement_Log** | History: mac, from/to lat/lng, distance, tracker, movement_time |
| **Trackers** | id, label, lat, lng, speed, last_update, battery_percent |
| **BLE_Pairing_History** | Pairing sessions: mac, tracker, start/end, duration, start/end lat/lng |
| **System_Config** | Key-value config |
| **vw_BLE_Diagnostics** | Optional view over BLE_Scans: aggregated per MAC (last_seen, avg_battery, etc.); see scripts/create_vw_BLE_Diagnostics.sql |

Schema is created by: `python setup_database.py` (and optionally scripts/create_vw_BLE_Diagnostics.sql if BLE_Scans exists).

---

## 4. Business Logic (Summary)

- **60-second rule:** A BLE asset’s position is updated only when the **same** tracker has detected it continuously for **> 60 seconds** (towing detection).
- **Broker:** First detection sets position (if tracker stopped); small moves (< 30 m) ignored (GPS drift); gap + significant move can update; pairing duration tracked per MAC/tracker.
- **Map:** Beacon data (battery, last saw) comes **only from broker** (or DB/vw_BLE_Diagnostics when broker has no live data). Navixy is used only for tracker positions and, in Both mode, to fill BLE position when broker has none.

---

## 5. Ports and Services

| Port | Service | Role |
|------|---------|------|
| 8080 | Map UI | index.html |
| 8767 | Navixy API | server.py – map source "Motorized GSE" |
| 8768 | Broker API | teltonika_broker.py – map source "Direct" |
| 15027 | Teltonika TCP | Devices connect here |

### Windows services (server + broker + tunnel from branch)
Install scripts use **repo root from script path** so the same broker/server logic (branch) runs as service:
- **NavixyApi** – `service\start_server.ps1` → server.py (8767)
- **NavixyBroker** – `service\start_broker.ps1` → teltonika_broker.py (15027, 8768)
- **NavixyTunnel** – `service\start_tunnel.ps1` → Cloudflare
- **NavixyDashboard** – optional, `service\start_dashboard.ps1`

See `service\install_services.ps1`, `service\install_services_with_dashboard.ps1`, `service\README_SERVICE.md`.

---

## 6. Version 001 – Drop Checklist

- [ ] All MDs combined/referenced in this doc
- [ ] Database schema in setup_database.py and docs/SQL_BLE_DATA_SPEC.md
- [ ] Broker: TCP 15027, HTTP 8768, /data, BLE parsing, 60s logic, DB + vw_BLE_Diagnostics
- [ ] Map: Direct / Both / Motorized GSE; broker-first merge; Battery & Last saw in popup
- [ ] Tunnel: Cloudflare named tunnel; fix_tunnel_permissions + start_tunnel.ps1; docs/CLOUDFLARE_TUNNEL_SETUP.md
- [ ] Branch main documented; Eyebecon-As-an-Asset merged and documented (docs/EYEBECON_BRANCH_SYNC.md)
- [ ] Repo pushed and synced; tag or backup for v001

---

*This file is the single entry point for Navixy Platform ELAL project system documentation. Last consolidated for version 001.*
