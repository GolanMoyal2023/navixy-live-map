# Navixy Live Map - BLE Asset Tracking System

## 🎯 Purpose

Real-time tracking and visualization of airport ground support equipment (GSE):
- **Motorized GSE** (tractors, tugs) with GPS trackers
- **Static Assets** (tow bars, loaders) with BLE beacons

## 🏗️ Architecture

```
┌──────────┐     ┌──────────┐
│  Eye     │◄BLE─│ FMC650   │
│  Beacons │     │ FMC003   │
└──────────┘     └────┬─────┘
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
┌───────────────┐         ┌────────────────┐
│    NAVIXY     │         │  LOCAL BROKER  │     ┌──────────┐
│   (Cloud)     │         │  (Port 15027)  │─────│ SQL      │
│   1 BLE/track │         │  ALL BLEs      │     │ Server   │
└───────┬───────┘         └───────┬────────┘     └──────────┘
        │                         │
        └────────────┬────────────┘
                     ▼
              ┌────────────┐
              │  MAP UI    │
              │ index.html │
              └────────────┘
```

## 📁 Key Files

| File | Purpose |
|------|---------|
| `index.html` | Map UI (Leaflet.js) |
| `server.py` | Navixy API server |
| `teltonika_broker.py` | Direct TCP broker |
| `db_helper.py` | SQL Server helper |
| `setup_database.py` | Database setup |

## 🚀 Quick Start (run locally)

**Terminal 1 – broker (TCP 15027 + HTTP 8768):**
```powershell
cd D:\2Plus\Services\navixy-live-map
.\.venv\Scripts\python.exe teltonika_broker.py
```

**Terminal 2 – test data + map:**
```powershell
cd D:\2Plus\Services\navixy-live-map
.\.venv\Scripts\python.exe send_test_avl.py   # optional: inject 1 tracker + BLE
.\run_local.ps1                                # starts map server, opens browser
```
Or manually: `python -m http.server 8080` then open **http://127.0.0.1:8080/index.html** and use **Data: Direct**.

**One-time setup:** `pip install flask requests pyodbc` in the venv; run `setup_database.py` if using SQL Server.

## 🔌 Ports

| Port | Service |
|------|---------|
| 8080 | Map UI |
| 8765 | Navixy API |
| 8768 | Broker API |
| 15027 | Teltonika TCP |

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture diagram |
| [BUSINESS_LOGIC.md](BUSINESS_LOGIC.md) | 60-second pairing logic |
| [SETUP_GUIDE.md](SETUP_GUIDE.md) | Installation steps |
| [TELTONIKA_CONFIG.md](TELTONIKA_CONFIG.md) | Device configuration |
| [docs/EYEBECON_BRANCH_SYNC.md](docs/EYEBECON_BRANCH_SYNC.md) | Eyebecon-as-asset branch vs main: single source, no duplication |
| [docs/NAVIXY_PLATFORM_ELAL_PROJECT.md](docs/NAVIXY_PLATFORM_ELAL_PROJECT.md) | **Combined system doc** – all MDs, data flow, DB schema, v001 checklist |

## 🏷️ BLE Asset Categories

| Category | Shape | Color | Use Case |
|----------|-------|-------|----------|
| Towed Device | ◆ Diamond | Purple | Tow bars |
| Equipment | ■ Square | Blue | Loaders |
| Safety | ▲ Triangle | Green | Safety gear |
| Container | ⬠ Pentagon | Orange | Cargo |

## 💡 Key Concept: 60-Second Pairing

BLE assets only update position when detected by the **same tracker for > 60 seconds**.

| Detection Time | Action |
|----------------|--------|
| < 60 sec | Tracker passing by - ignore |
| > 60 sec | Being towed - update position |

See [BUSINESS_LOGIC.md](BUSINESS_LOGIC.md) for details.

## 🔧 Maintenance

```powershell
# Check services
Get-Service Navixy*

# Restart services
Get-Service Navixy* | Restart-Service

# View broker logs
Get-Content terminals\26.txt -Tail 50
```

## 📞 Support

- **Navixy API Docs:** https://api.navixy.com/
- **Teltonika Wiki:** https://wiki.teltonika-gps.com/

---

*Built for ELAL Airport GSE Tracking POC*
