# Eyebeacon Asset Tracking System - Server Deployment Guide

Complete guide to deploy the Eyebeacon Asset Tracking System on your server.

---

## 📋 Table of Contents

1. [System Requirements](#system-requirements)
2. [Database Setup (SQL Server)](#database-setup-sql-server)
3. [Firewall Configuration](#firewall-configuration)
4. [Python Environment](#python-environment)
5. [Configuration Files](#configuration-files)
6. [Running the Services](#running-the-services)
7. [Teltonika Device Configuration](#teltonika-device-configuration)
8. [Verification & Testing](#verification--testing)
9. [Troubleshooting](#troubleshooting)

---

## 1. System Requirements

### Hardware (Minimum)
| Component | Requirement |
|-----------|-------------|
| CPU | 2 cores |
| RAM | 4 GB |
| Storage | 20 GB SSD |
| Network | Static IP or DDNS |

### Software
| Software | Version | Purpose |
|----------|---------|---------|
| Windows Server | 2019+ or Windows 10/11 | Operating System |
| Python | 3.10+ | Runtime |
| SQL Server | 2019+ (Express OK) | Database |
| ODBC Driver | 17+ for SQL Server | Database connectivity |
| Git | Latest | Version control |

---

## 2. Database Setup (SQL Server)

### 2.1 Install SQL Server Express

If not already installed:
```powershell
# Download SQL Server Express 2022
# https://www.microsoft.com/en-us/sql-server/sql-server-downloads

# During installation:
# - Choose "Basic" installation
# - Note the instance name (e.g., SQLEXPRESS or SQL2025)
# - Enable Mixed Mode Authentication
# - Set SA password
```

### 2.2 Install ODBC Driver

```powershell
# Download ODBC Driver 17 for SQL Server
# https://docs.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server
```

### 2.3 Create Database and Tables

Run the setup script:

```powershell
cd D:\YourPath\navixy-live-map
python setup_database.py
```

**Or manually create the database:**

```sql
-- Create Database
CREATE DATABASE [2Plus_AssetTracking];
GO

USE [2Plus_AssetTracking];
GO

-- BLE Definitions (Known beacons)
CREATE TABLE BLE_Definitions (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) NOT NULL UNIQUE,
    name NVARCHAR(100) NOT NULL,
    category NVARCHAR(50) DEFAULT 'Equipment',
    ble_type VARCHAR(30) DEFAULT 'eye_beacon',
    serial_number VARCHAR(50),
    asset_id VARCHAR(50),
    notes NVARCHAR(500),
    created_at DATETIME DEFAULT GETDATE(),
    is_active BIT DEFAULT 1
);

-- BLE Positions (Current position of each beacon)
CREATE TABLE BLE_Positions (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) NOT NULL UNIQUE,
    lat DECIMAL(10, 7),
    lng DECIMAL(10, 7),
    last_tracker_id VARCHAR(50),
    last_tracker_label NVARCHAR(100),
    last_update DATETIME DEFAULT GETDATE(),
    is_paired BIT DEFAULT 0,
    pairing_start DATETIME,
    pairing_duration_sec INT DEFAULT 0,
    battery_percent INT,
    magnet_status VARCHAR(20),
    name NVARCHAR(100),
    category NVARCHAR(50),
    ble_type VARCHAR(30),
    serial_number VARCHAR(50)
);

-- BLE Movement Log (History of position changes)
CREATE TABLE BLE_Movement_Log (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) NOT NULL,
    from_lat DECIMAL(10, 7),
    from_lng DECIMAL(10, 7),
    to_lat DECIMAL(10, 7),
    to_lng DECIMAL(10, 7),
    distance_meters FLOAT,
    tracker_id VARCHAR(50),
    tracker_label NVARCHAR(100),
    pairing_duration_sec INT,
    moved_at DATETIME DEFAULT GETDATE()
);

-- BLE Scans (Raw scan history for diagnostics)
CREATE TABLE BLE_Scans (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) NOT NULL,
    lat DECIMAL(10, 7),
    lng DECIMAL(10, 7),
    tracker_imei VARCHAR(20),
    tracker_label NVARCHAR(100),
    rssi INT,
    battery_percent INT,
    distance_meters FLOAT,
    magnet_status VARCHAR(20),
    is_known_beacon BIT DEFAULT 0,
    scan_time DATETIME DEFAULT GETDATE()
);

-- Trackers (Vehicle/device info)
CREATE TABLE Trackers (
    id INT PRIMARY KEY,
    label NVARCHAR(100),
    lat DECIMAL(10, 7),
    lng DECIMAL(10, 7),
    speed FLOAT,
    device_type VARCHAR(50),
    category VARCHAR(50),
    battery_percent INT,
    last_update DATETIME DEFAULT GETDATE()
);

-- System Config
CREATE TABLE System_Config (
    config_key VARCHAR(50) PRIMARY KEY,
    config_value NVARCHAR(500),
    description NVARCHAR(200),
    updated_at DATETIME DEFAULT GETDATE()
);

-- Create indexes for performance
CREATE INDEX IX_BLE_Scans_mac_time ON BLE_Scans(mac, scan_time);
CREATE INDEX IX_BLE_Movement_mac ON BLE_Movement_Log(mac);
CREATE INDEX IX_BLE_Positions_mac ON BLE_Positions(mac);
```

### 2.4 Insert Your BLE Beacons

```sql
-- Insert your known beacons
INSERT INTO BLE_Definitions (mac, name, category, ble_type, serial_number) VALUES
('7cd9f407f95c', 'Eybe2plus1', 'Towed Device', 'eye_beacon', '6204011070'),
('7cd9f4003536', 'Eybe2plus2', 'Equipment', 'eye_beacon', '6204011168'),
('7cd9f4116ee7', 'Eysen2plus', 'Safety', 'eye_sensor', '6134010143'),
('7cd9f406427b', 'EyeBe3', 'Equipment', 'eye_beacon', ''),
('7cd9f407a2db', 'EyeBe4', 'Equipment', 'eye_beacon', '');

-- Initialize positions (set to your home/base location)
INSERT INTO BLE_Positions (mac, lat, lng, name, category, ble_type, serial_number) VALUES
('7cd9f407f95c', 32.310117, 34.932402, 'Eybe2plus1', 'Towed Device', 'eye_beacon', '6204011070'),
('7cd9f4003536', 32.310117, 34.932402, 'Eybe2plus2', 'Equipment', 'eye_beacon', '6204011168'),
('7cd9f4116ee7', 32.310117, 34.932402, 'Eysen2plus', 'Safety', 'eye_sensor', '6134010143'),
('7cd9f406427b', 32.310117, 34.932402, 'EyeBe3', 'Equipment', 'eye_beacon', ''),
('7cd9f407a2db', 32.310117, 34.932402, 'EyeBe4', 'Equipment', 'eye_beacon', '');
```

---

## 3. Firewall Configuration

### 3.1 Required Ports

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| **15027** | TCP | Inbound | Teltonika device connections (CODEC8) |
| **8768** | TCP | Inbound | HTTP API for map (internal) |
| **8080** | TCP | Inbound | Map UI (optional, for web access) |
| **1433** | TCP | Local | SQL Server (usually localhost only) |

### 3.2 Windows Firewall Setup

Run as Administrator:

```powershell
# Allow Teltonika TCP connections (REQUIRED for devices)
New-NetFirewallRule -DisplayName "Teltonika Broker TCP" `
    -Direction Inbound -Protocol TCP -LocalPort 15027 `
    -Action Allow -Profile Any

# Allow HTTP API (for map)
New-NetFirewallRule -DisplayName "Teltonika Broker HTTP" `
    -Direction Inbound -Protocol TCP -LocalPort 8768 `
    -Action Allow -Profile Any

# Allow Map UI (optional)
New-NetFirewallRule -DisplayName "Map UI HTTP" `
    -Direction Inbound -Protocol TCP -LocalPort 8080 `
    -Action Allow -Profile Any

# Verify rules
Get-NetFirewallRule -DisplayName "Teltonika*" | Format-Table Name, Enabled, Direction
```

### 3.3 Router/Cloud Firewall

If your server is behind a router or cloud firewall:

```
Port Forward: External:15027 → Server_IP:15027 (TCP)
Port Forward: External:8768 → Server_IP:8768 (TCP)  # Optional
```

**Important:** Your Teltonika devices need to connect to your server's **public IP:15027**

---

## 4. Python Environment

### 4.1 Install Python

```powershell
# Download Python 3.10+ from python.org
# During install: ✅ Add to PATH

# Verify installation
python --version  # Should show 3.10+
```

### 4.2 Create Virtual Environment

```powershell
cd D:\YourPath\navixy-live-map

# Create virtual environment
python -m venv .venv

# Activate
.\.venv\Scripts\Activate

# Verify
where python  # Should show .venv path
```

### 4.3 Install Dependencies

```powershell
# Install required packages
pip install flask requests pyodbc

# Or use requirements.txt
pip install -r requirements.txt
```

**requirements.txt:**
```
flask>=2.0.0
requests>=2.28.0
pyodbc>=4.0.35
```

---

## 5. Configuration Files

### 5.1 Database Connection (db_helper.py)

Edit the connection settings:

```python
# db_helper.py - Line 11-14
SQL_SERVER = r"localhost\SQLEXPRESS"  # Your SQL instance name
SQL_DATABASE = "2Plus_AssetTracking"
SQL_USER = "sa"                        # SQL username
SQL_PASSWORD = "YourPassword"          # SQL password
```

### 5.2 Broker Configuration (teltonika_broker.py)

Edit the port and threshold settings:

```python
# teltonika_broker.py - Line 44-54
TCP_HOST = "0.0.0.0"
TCP_PORT = 15027          # Teltonika devices connect here
HTTP_PORT = 8768          # Map API endpoint

# Position update thresholds
PAIRING_THRESHOLD_SEC = 60    # 60 seconds for towing confirmation
GPS_DRIFT_THRESHOLD_M = 30    # Ignore movements < 30m (GPS drift)
GAP_THRESHOLD_SEC = 300       # 5 minutes = detection gap
SIGNIFICANT_MOVE_M = 100      # Movement > 100m after gap = new placement
MAX_SPEED_KMH = 5             # Only update when speed < 5 km/h
```

### 5.3 Known BLE Beacons

Add your beacons in `teltonika_broker.py`:

```python
# teltonika_broker.py - Line 72-80
ble_definitions: Dict[str, Dict[str, Any]] = {
    "7cd9f407f95c": {"name": "Eybe2plus1", "category": "Towed Device", "type": "eye_beacon", "sn": "6204011070"},
    "7cd9f4003536": {"name": "Eybe2plus2", "category": "Equipment", "type": "eye_beacon", "sn": "6204011168"},
    "7cd9f4116ee7": {"name": "Eysen2plus", "category": "Safety", "type": "eye_sensor", "sn": "6134010143"},
    "7cd9f406427b": {"name": "EyeBe3", "category": "Equipment", "type": "eye_beacon", "sn": ""},
    "7cd9f407a2db": {"name": "EyeBe4", "category": "Equipment", "type": "eye_beacon", "sn": ""},
}
```

**To find your beacon MAC addresses:**
1. Use Teltonika Configurator → Bluetooth → Scan
2. Or check the beacon's physical label

---

## 6. Running the Services

### 6.1 Manual Start (Development/Testing)

**Terminal 1: Teltonika Broker (REQUIRED)**
```powershell
cd D:\YourPath\navixy-live-map
.\.venv\Scripts\Activate
python teltonika_broker.py
```

Expected output:
```
============================================================
Teltonika Direct Broker Starting
============================================================
TCP Port (Devices): 15027
HTTP Port (API): 8768
Database: Enabled
Known BLE Definitions: 5
============================================================
[DB] Connected to 2Plus_AssetTracking
[DB] Loaded 5 BLE definitions
[DB] Loaded 5 stored BLE positions
[HTTP] API server starting on port 8768
```

**Terminal 2: Map UI (Optional)**
```powershell
cd D:\YourPath\navixy-live-map
python -m http.server 8080
```

### 6.2 Windows Service (Production)

Use NSSM to install as a Windows Service:

```powershell
# Download NSSM from https://nssm.cc/download

# Install broker as service
nssm install TeltonikaBroker "D:\YourPath\navixy-live-map\.venv\Scripts\python.exe" "D:\YourPath\navixy-live-map\teltonika_broker.py"
nssm set TeltonikaBroker AppDirectory "D:\YourPath\navixy-live-map"
nssm set TeltonikaBroker DisplayName "Teltonika BLE Broker"
nssm set TeltonikaBroker Start SERVICE_AUTO_START

# Start the service
nssm start TeltonikaBroker

# Check status
Get-Service TeltonikaBroker
```

### 6.3 Startup Script (Alternative)

Create `start_broker.bat`:
```batch
@echo off
cd /d D:\YourPath\navixy-live-map
call .venv\Scripts\activate.bat
python teltonika_broker.py
pause
```

---

## 7. Teltonika Device Configuration

### 7.1 Server Configuration

In Teltonika Configurator:

```
GPRS → Server Settings:
  Domain: YOUR_SERVER_IP
  Port: 15027
  Protocol: TCP
  
Data → Codec: Codec 8 Extended (REQUIRED for BLE)
```

### 7.2 Bluetooth Settings

```
Bluetooth → Settings:
  BT Radio: Enabled
  Non Stop Scan: ON
  BT Power Level: High (+12 dBm)
  
Bluetooth → Beacon Parsing Mode: Advanced (NOT Simple!)

Bluetooth → Beacon List:
  Add your EYE Beacon MACs
```

### 7.3 Data Acquisition Settings (FMC003/FMC650)

```
Data Acquisition:
  On Stop:
    Min Period: 60 sec
    Saved Records: 60 sec
    Send Period: 60 sec
    
  On Move:
    Min Period: 5 sec (for testing) or 30 sec (production)
    Saved Records: 5 sec
    Send Period: 10 sec
    
  Min Saved Records: 1
```

### 7.4 IO Elements

Enable these AVL IDs:
- **385**: BLE Beacons Seen (array)
- **10828, 10829, 11317**: FMC003 custom beacon elements
- **181**: GNSS Status
- **200**: Sleep Mode

---

## 8. Verification & Testing

### 8.1 Test Database Connection

```powershell
cd D:\YourPath\navixy-live-map
.\.venv\Scripts\python.exe db_helper.py
```

Expected:
```
Testing database connection...
[OK] Connected to SQL Server
[OK] Found 5 BLE definitions
  - Eybe2plus1 (7cd9f407f95c)
  - Eybe2plus2 (7cd9f4003536)
  ...
[OK] Found 5 BLE positions
```

### 8.2 Test HTTP API

```powershell
# Test broker status
Invoke-RestMethod "http://127.0.0.1:8768/"

# Test data endpoint
Invoke-RestMethod "http://127.0.0.1:8768/data" | ConvertTo-Json -Depth 5
```

### 8.3 Test TCP Port

```powershell
# Check if port is listening
netstat -ano | findstr ":15027"

# Test TCP connection
Test-NetConnection -ComputerName localhost -Port 15027
```

### 8.4 Monitor Device Connections

Watch the broker console for:
```
[TCP] Connection from ('1.2.3.4', 12345)
[TCP] Device authenticated: IMEI 864275078490847
[TCP] 864275078490847: Received 256 bytes
[TCP] 864275078490847: 3 beacons at (32.310000, 34.930000), Speed: 0 km/h
```

---

## 9. Troubleshooting

### Issue: "Connection refused" on port 15027

```powershell
# Check if broker is running
Get-Process python

# Check if port is in use
netstat -ano | findstr ":15027"

# Restart broker
Stop-Process -Name python -Force
python teltonika_broker.py
```

### Issue: "Database connection failed"

```powershell
# Test SQL Server connection
sqlcmd -S localhost\SQLEXPRESS -U sa -P YourPassword -Q "SELECT 1"

# Check SQL Server service
Get-Service MSSQL*

# Verify ODBC driver
odbcad32.exe  # Check "Drivers" tab
```

### Issue: "Devices not connecting"

1. **Verify server IP:** Device must have correct public IP
2. **Check firewall:** Port 15027 must be open inbound
3. **Check router:** Port forward must be configured
4. **Check device config:** Protocol must be TCP, port 15027, Codec 8 Extended

### Issue: "Beacons not detected"

1. **Check Bluetooth enabled** on Teltonika device
2. **Check beacon battery** (minimum 2.8V)
3. **Check Beacon Parsing Mode:** Must be "Advanced" not "Simple"
4. **Check beacon MAC** is in `ble_definitions`

### Issue: "Positions drifting"

1. **Verify speed filter:** `MAX_SPEED_KMH = 5`
2. **Verify GPS drift filter:** `GPS_DRIFT_THRESHOLD_M = 30`
3. **Check pairing threshold:** `PAIRING_THRESHOLD_SEC = 60`

---

## 📊 Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                     TELTONIKA DEVICES                        │
│              (FMC003/FMC650 with BLE beacons)                │
└────────────────────────┬────────────────────────────────────┘
                         │ TCP/CODEC8 (Port 15027)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   TELTONIKA BROKER                           │
│                  (teltonika_broker.py)                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │ TCP Server  │  │ BLE Position │  │    HTTP API         │ │
│  │ Port 15027  │→ │    Logic     │→ │   Port 8768         │ │
│  │ CODEC8 Parse│  │ 60s Pairing  │  │   /data endpoint    │ │
│  └─────────────┘  │ Speed Filter │  └─────────────────────┘ │
│                   │ GPS Drift    │                          │
│                   └──────┬───────┘                          │
└──────────────────────────┼──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    SQL SERVER DATABASE                       │
│                  (2Plus_AssetTracking)                       │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────────┐  │
│  │BLE_Definitions│ │ BLE_Positions │ │ BLE_Scans         │  │
│  │(known beacons)│ │(current locs) │ │(scan history)     │  │
│  └───────────────┘ └───────────────┘ └───────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      MAP UI (index.html)                     │
│                   Leaflet.js + API polling                   │
│              http://server:8080/index.html                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔑 Quick Reference

### Ports
| Port | Service |
|------|---------|
| 15027 | Teltonika TCP (devices connect here) |
| 8768 | HTTP API (map data) |
| 8080 | Map UI (web interface) |
| 1433 | SQL Server |

### API Endpoints
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Broker status |
| `/data` | GET | All tracker and BLE data |
| `/ble/positions` | GET | BLE positions only |
| `/ble/set-position` | POST | Manually set beacon position |
| `/ble/set-all-home` | POST | Reset all beacons to home |

### Key Files
| File | Purpose |
|------|---------|
| `teltonika_broker.py` | Main broker (TCP + HTTP) |
| `db_helper.py` | Database operations |
| `setup_database.py` | Create DB tables |
| `index.html` | Map UI |
| `record_trip.py` | Trip recording tool |

---

## 📞 Support

- **GitHub:** https://github.com/GolanMoyal2023/navixy-live-map
- **Branch:** `main` (contains all from `Eyebecon-As-an-Asset`; see [docs/EYEBECON_BRANCH_SYNC.md](docs/EYEBECON_BRANCH_SYNC.md))
- **Documentation:** See `ARCHITECTURE.md`, `BUSINESS_LOGIC.md`, `TELTONIKA_CONFIG.md`

---

*Last Updated: February 2026*
