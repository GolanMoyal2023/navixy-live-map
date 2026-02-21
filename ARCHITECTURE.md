# Navixy Live Map - System Architecture

## Overview

This system provides real-time tracking and visualization of:
- **GSE (Ground Support Equipment)** - Motorized vehicles with GPS trackers (FMC650/FMC003)
- **BLE Assets** - Static equipment with Teltonika Eye Beacons/Sensors (tow bars, cargo loaders, etc.)

## Data Flow Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          DATA FLOW ARCHITECTURE                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────┐                                                               │
│   │  Eye     │◄──── BLE ────┐                                                │
│   │  Beacons │              │                                                │
│   │  Sensors │              │                                                │
│   └──────────┘              ▼                                                │
│                       ┌──────────┐                                           │
│                       │ FMC650   │                                           │
│                       │ FMC003   │                                           │
│                       └────┬─────┘                                           │
│                            │                                                 │
│              ┌─────────────┴─────────────┐                                   │
│              │ TCP                   TCP │                                   │
│              ▼                           ▼                                   │
│   ┌─────────────────┐         ┌────────────────┐                             │
│   │    NAVIXY       │         │  YOUR BROKER   │                             │
│   │    PLATFORM     │         │  (TCP:15027)   │                             │
│   │                 │         │                │    ┌──────────┐             │
│   │  - Cloud hosted │         │  - Local       │    │  SQL     │             │
│   │  - 1 BLE limit  │         │  - ALL BLEs    │────│  Server  │             │
│   │                 │         │  - 60s Logic   │    │  Express │             │
│   └────────┬────────┘         └───────┬────────┘    └──────────┘             │
│            │                          │                                      │
│      HTTP API                    HTTP:8768                                   │
│      (Navixy)                    (Broker)                                    │
│            │                          │                                      │
│            ▼                          ▼                                      │
│   ┌─────────────────┐         ┌────────────────┐                             │
│   │  API Server     │         │  (same server) │                             │
│   │  (Port 8765/67) │         │                │                             │
│   └────────┬────────┘         └───────┬────────┘                             │
│            │                          │                                      │
│            └──────────┬───────────────┘                                      │
│                       │                                                      │
│                       ▼                                                      │
│            ┌──────────────────┐                                              │
│            │     MAP UI       │                                              │
│            │   index.html     │                                              │
│            │                  │                                              │
│            │  [Navixy] [Direct]  ◄── Toggle between data sources             │
│            └──────────────────┘                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Teltonika Trackers (FMC650 / FMC003)

GPS tracking devices installed on motorized GSE vehicles.

| Feature | Description |
|---------|-------------|
| **GPS** | Real-time location, speed, heading |
| **BLE** | Detects nearby Eye Beacons/Sensors |
| **Protocol** | CODEC8 Extended over TCP |
| **Dual Send** | Can send to both Navixy AND local broker |

### 2. Teltonika Eye Beacons/Sensors

BLE devices attached to static/towed equipment.

| Device | Type | Data | Use Case |
|--------|------|------|----------|
| **Eye Beacon** | BLE Tag | Battery, Temperature | Tow bars, Cargo loaders |
| **Eye Sensor** | BLE Sensor | Battery, Magnet status, Humidity | Doors, Containers |

**Current Devices:**

| Name | MAC | Category | S/N |
|------|-----|----------|-----|
| Eybe2plus1 | f008d1d55c3c | Towed Device | 6204011070 |
| Eybe2plus2 | f008d1d54c72 | Equipment | 6204011168 |
| Eysen2plus | f008d1d516fb | Safety | 6134010143 |

### 3. Data Sources

#### Option A: Navixy Platform (Cloud)

```
FMC650 → Navixy Cloud → API → Local Server → Map
```

| Pros | Cons |
|------|------|
| ✅ Already configured | ❌ 1 BLE per tracker limit |
| ✅ Cloud reliability | ❌ API rate limits |
| ✅ Historical data | ❌ No raw data access |

#### Option B: Direct Broker (Local)

```
FMC650 → Local Broker → SQL Server → Map
```

| Pros | Cons |
|------|------|
| ✅ ALL BLEs captured | ❌ Requires local server |
| ✅ Full data control | ❌ No cloud backup |
| ✅ Custom logic | ❌ Device reconfiguration |
| ✅ SQL storage | |

### 4. SQL Server Database

| Table | Purpose |
|-------|---------|
| `BLE_Definitions` | Known BLE devices (MAC, name, category) |
| `BLE_Positions` | Current BLE positions (persisted) |
| `BLE_Movement_Log` | Position change history |
| `BLE_Pairing_History` | Tracker-BLE pairing sessions |
| `Trackers` | GSE/Vehicle positions |
| `System_Config` | Configuration values |

### 5. Map UI (index.html)

Interactive Leaflet.js map showing:
- GSE trackers with real-time positions
- BLE assets with category-based icons
- Toggle between Navixy and Direct data sources
- Airport overlay (runways, taxiways, gates)

## Ports Summary

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 8080 | HTTP Server | HTTP | Serve map UI (index.html) |
| 8765 | Navixy API Server | HTTP | Fetch data from Navixy |
| 8767 | DB-Enabled API | HTTP | Same as 8765 with SQL |
| 8768 | Direct Broker API | HTTP | Data from direct broker |
| 15027 | Teltonika Broker | TCP | Receive device data |
| 1433 | SQL Server | TCP | Database |

## File Structure

```
navixy-live-map/
├── index.html              # Main map UI
├── server.py               # Navixy API server
├── teltonika_broker.py     # Direct TCP broker + API
├── db_helper.py            # SQL Server helper
├── setup_database.py       # Database schema setup
├── llbg_layers.geojson     # Airport overlay
├── Pictures/               # Asset icons
│   └── TowBar.png
├── service/                # Windows service scripts
│   ├── install_*.ps1
│   └── start_*.ps1
└── *.md                    # Documentation
```

## Next Steps

1. See [BUSINESS_LOGIC.md](BUSINESS_LOGIC.md) for BLE pairing rules
2. See [SETUP_GUIDE.md](SETUP_GUIDE.md) for installation
3. See [TELTONIKA_CONFIG.md](TELTONIKA_CONFIG.md) for device setup
