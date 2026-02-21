# Setup Guide

## Prerequisites

- Windows 10/11 or Windows Server
- Python 3.10+
- SQL Server Express (localhost\SQL2025)
- NSSM (for Windows services)
- Git

## Quick Start

### 1. Clone Repository

```powershell
cd D:\2Plus\Services
git clone <your-repo-url> navixy-live-map
cd navixy-live-map
```

### 2. Setup Python Environment

```powershell
python -m venv .venv
.\.venv\Scripts\activate
pip install flask requests pyodbc
```

### 3. Setup Database

```powershell
.\.venv\Scripts\python.exe setup_database.py
```

Expected output:
```
[OK] Database 2Plus_AssetTracking ready
[OK] Created/verified: BLE_Positions
[OK] Created/verified: BLE_Movement_Log
...
[SUCCESS] DATABASE SETUP COMPLETE!
```

### 4. Start Services

#### Option A: Manual (Development)

```powershell
# Terminal 1: HTTP Server (serves map)
cd D:\2Plus\Services\navixy-live-map
python -m http.server 8080

# Terminal 2: Navixy API Server
$env:NAVIXY_API_HASH = "your_hash_here"
.\.venv\Scripts\python.exe server.py

# Terminal 3: Teltonika Direct Broker
.\.venv\Scripts\python.exe teltonika_broker.py
```

#### Option B: Windows Services (Production)

```powershell
# Run as Administrator
cd D:\New_Recovery\2Plus\navixy-live-map\service
.\install_all_services.ps1
```

### 5. Access Map

Open browser: `http://127.0.0.1:8080/index.html`

## Port Summary

| Port | Service | Command to Start |
|------|---------|------------------|
| 8080 | Map UI | `python -m http.server 8080` |
| 8765 | Navixy API | `python server.py` (PORT=8765) |
| 8767 | DB-Enabled API | `python server.py` (PORT=8767) |
| 8768 | Direct Broker | `python teltonika_broker.py` |
| 15027 | Teltonika TCP | (part of broker) |

## Verify Installation

### Test API Server

```powershell
Invoke-RestMethod "http://127.0.0.1:8767/data" | ConvertTo-Json
```

### Test Direct Broker

```powershell
Invoke-RestMethod "http://127.0.0.1:8768/" | ConvertTo-Json
```

### Test Database Connection

```powershell
.\.venv\Scripts\python.exe db_helper.py
```

## Configuration Files

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| NAVIXY_API_HASH | (required) | Navixy API authentication hash |
| NAVIXY_BASE_URL | api.navixy.com/v2 | Navixy API base URL |
| PORT | 8080 | API server port |

### Database Connection

Edit `db_helper.py`:

```python
SQL_SERVER = r"localhost\SQL2025"
SQL_DATABASE = "2Plus_AssetTracking"
SQL_USER = "sa"
SQL_PASSWORD = "P@ssword0"
```

## Troubleshooting

### "Connection refused" on port 8080

```powershell
# Check if server is running
netstat -ano | findstr ":8080"

# Start if not running
cd D:\New_Recovery\2Plus\navixy-live-map
python -m http.server 8080
```

### "NAVIXY_API_HASH not set"

```powershell
$env:NAVIXY_API_HASH = "your_hash_here"
```

### Database connection error

1. Verify SQL Server is running
2. Check credentials in `db_helper.py`
3. Run `setup_database.py` again

### Multiple Python processes on same port

```powershell
# Find and kill processes
Get-Process python | Stop-Process -Force
```

## Windows Services

### Service Names

| Service | Description |
|---------|-------------|
| NavixyApi | Navixy API server (port 8765) |
| NavixyQuickTunnel | Cloudflare tunnel for external access |
| NavixyDashboard | Monitoring dashboard (port 8766) |
| NavixyUrlSync | Automatic GitHub sync |

### Manage Services

```powershell
# Check status
Get-Service Navixy*

# Restart all
Get-Service Navixy* | Restart-Service

# View logs
Get-Content D:\New_Recovery\2Plus\navixy-live-map\logs\api.log -Tail 50
```

## Next Steps

1. Configure Teltonika devices: [TELTONIKA_CONFIG.md](TELTONIKA_CONFIG.md)
2. Understand business logic: [BUSINESS_LOGIC.md](BUSINESS_LOGIC.md)
3. Review architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
