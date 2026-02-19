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

## 🚀 Quick Start

```powershell
# 1. Setup
cd D:\New_Recovery\2Plus\navixy-live-map
.\.venv\Scripts\activate
pip install flask requests pyodbc

# 2. Database
.\.venv\Scripts\python.exe setup_database.py

# 3. Start servers
python -m http.server 8080                    # Map UI
.\.venv\Scripts\python.exe teltonika_broker.py  # Broker

# 4. Open map
start http://127.0.0.1:8080/index.html
```

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
