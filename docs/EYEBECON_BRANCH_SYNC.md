# Eyebecon-as-Asset Branch vs Main – Single Source, No Duplication

**Branch:** `origin/Eyebecon-As-an-Asset`  
**Current:** `main`

Main contains **all** broker and Eyebecon-as-asset logic from the Eyebecon branch, plus scripts and docs added later. Nothing from that branch is duplicated; everything is in one place.

---

## 1. Broker & BLE Asset – Where It Lives (no duplication)

| What | File(s) | Notes |
|------|--------|--------|
| **Teltonika TCP/HTTP broker** | `teltonika_broker.py` | Single broker: TCP 15027, HTTP 8768, `/data`, BLE parsing, 60s pairing, SQL |
| **DB access** | `db_helper.py` | BLE_Positions, BLE_Definitions, get_all_ble_positions, update_ble_position |
| **DB schema & seed** | `setup_database.py` | Creates BLE_Positions, BLE_Definitions, etc. |
| **BLE tables (alternate)** | `create_ble_tables.py` | Optional table creation script |
| **Map: BLE from API** | `index.html` | `updateBeaconMarkersFromSQL(blePositionsData, trackerRows)` – only uses `ble_positions` from API |
| **Map: beacon popup** | `index.html` | `beaconPopupHtml(beacon)` – battery, last saw, BLE position info |
| **Map: data source** | `index.html` | Direct = broker 8768; Both = broker + Navixy; broker = source for battery/last_update |
| **Known beacons** | `index.html` + `teltonika_broker.py` | `KNOWN_BEACONS` in index; `ble_definitions` in broker (and DB) |
| **Fallback positions** | `index.html` | `DIRECT_BEACON_POSITIONS_FALLBACK` when broker has no position |

---

## 2. Eyebecon Branch vs Main – Coverage

| In Eyebecon branch | In main | Status |
|-------------------|---------|--------|
| `teltonika_broker.py` | Same file, same logic (+ file logging, [CATCH]/[BLE_STORE]/[DATA] logs) | ✅ Covered, no duplicate |
| `db_helper.py` | Same | ✅ Covered |
| `index.html` – updateBeaconMarkersFromSQL | Same pattern; main adds Both mode, merge broker-first, lastSeenAt, formatLastSaw | ✅ Covered + extended |
| `index.html` – DATA_SOURCES | Main: motorized_gse, direct, both + config.js / api-url | ✅ Covered + extended |
| `README.md`, `ARCHITECTURE.md`, `BUSINESS_LOGIC.md`, `TELTONIKA_CONFIG.md` | All on main | ✅ Covered |
| `setup_database.py`, `create_ble_tables.py` | On main | ✅ Covered |
| `setup_broker_firewall.ps1`, `start_teltonika_server.ps1` | On main | ✅ Covered |
| No scripts/seed on branch | Main has `scripts/run_seed_beacon_data.py`, `scripts/seed_beacon_data.sql`, `scripts/BEACON_DATA_REFERENCE.md` | ✅ Main adds seed; no duplicate |
| No start_all / recovery / ngrok on branch | Main has `start_all.ps1`, `service/recovery.ps1`, `service/start_ngrok_tunnel.ps1` | ✅ Main adds; no duplicate |

---

## 3. Single Place for Each Concern

- **Broker logic:** only in `teltonika_broker.py`.
- **BLE position storage/API:** only in `db_helper.py` + broker’s use of it.
- **Map BLE display:** only in `index.html` (updateBeaconMarkersFromSQL, beaconPopupHtml, loadData/merge).
- **Beacon definitions:** broker `ble_definitions` (+ DB BLE_Definitions); map `KNOWN_BEACONS` for display only.
- **Seed/import data:** `scripts/seed_beacon_data.sql`, `scripts/run_seed_beacon_data.py`, `scripts/import_ble_from_csv.py`, `docs/SQL_BLE_DATA_SPEC.md`.

---

## 4. Quick Checklist – “Cover All”

- [x] Broker runs and serves `/data` with `ble_positions` (battery, last_update, lat, lng, etc.).
- [x] Map uses broker for Direct and for Both (broker-first merge; Navixy only for missing position).
- [x] Popup shows Battery and Last saw from broker (or SQL when loaded from DB).
- [x] SQL used as start point: broker loads BLE_Positions at startup; `/data` merges DB when needed.
- [x] One script to start: `start_all.ps1` (or run broker + map as in README).
- [x] Docs: ARCHITECTURE, BUSINESS_LOGIC, TELTONIKA_CONFIG, MAINTENANCE, SQL_BLE_DATA_SPEC, BEACON_DATA_REFERENCE.

---

*Use this doc to confirm nothing from the Eyebecon-as-asset branch is missing or duplicated on main.*
