image.png# Navixy Live Map - Service Architecture Guide

> **Purpose:** This document explains the 4-service Windows architecture for the Navixy Live Map system. Use this guide to understand, troubleshoot, and manage the services.

---

## 📋 Table of Contents

1. [System Overview](#system-overview)
2. [The 4 Services Explained](#the-4-services-explained)
3. [Service Dependencies & Startup Order](#service-dependencies--startup-order)
4. [Data Flow Diagram](#data-flow-diagram)
5. [File Structure](#file-structure)
6. [Configuration Files](#configuration-files)
7. [Service Management Commands](#service-management-commands)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Installation Steps](#installation-steps)

---

## System Overview

The Navixy Live Map system provides **real-time GPS tracking visualization** with:
- **Local access** via `http://localhost:8765`
- **External access** via Cloudflare tunnel → GitHub Pages
- **Automatic recovery** after system restart (no human intervention)

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         NAVIXY LIVE MAP SYSTEM                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐    ┌──────────────────┐    ┌─────────────────────┐    │
│  │   NAVIXY    │    │   NavixyApi      │    │  NavixyQuickTunnel  │    │
│  │   CLOUD     │───▶│   (Flask:8765)   │───▶│   (Cloudflare)      │    │
│  │   API       │    │                  │    │                     │    │
│  └─────────────┘    └────────┬─────────┘    └──────────┬──────────┘    │
│                              │                         │               │
│                              │                         │               │
│                              ▼                         ▼               │
│                    ┌─────────────────┐      ┌─────────────────────┐    │
│                    │ NavixyDashboard │      │   NavixyUrlSync     │    │
│                    │   (Flask:8766)  │      │   (GitHub Push)     │    │
│                    └─────────────────┘      └──────────┬──────────┘    │
│                              │                         │               │
│                              ▼                         ▼               │
│                    ┌─────────────────┐      ┌─────────────────────┐    │
│                    │  LOCAL BROWSER  │      │   GITHUB PAGES      │    │
│                    │  Dashboard UI   │      │   External Map      │    │
│                    └─────────────────┘      └─────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## The 4 Services Explained

### 1️⃣ NavixyApi (Flask API Server)

| Property | Value |
|----------|-------|
| **Port** | 8765 |
| **Script** | `service\start_server.ps1` |
| **Main File** | `server.py` |
| **Dependencies** | None (starts first) |

**What it does:**
- Connects to Navixy Cloud API using `NAVIXY_API_HASH`
- Fetches real-time GPS data for tracked vehicles
- Serves data as JSON at `/data` endpoint
- Provides the local map interface at `/`

**Key Endpoints:**
```
GET http://localhost:8765/        → Local map UI
GET http://localhost:8765/data    → JSON GPS data
GET http://localhost:8765/health  → Health check
```

**Environment Variable Required:**
```powershell
$env:NAVIXY_API_HASH = "your_api_hash_here"
```

---

### 2️⃣ NavixyQuickTunnel (Cloudflare Tunnel)

| Property | Value |
|----------|-------|
| **External URL** | Dynamic (e.g., `https://xxx-yyy-zzz.trycloudflare.com`) |
| **Script** | `service\start_quick_tunnel.ps1` |
| **Dependencies** | NavixyApi must be running |
| **URL File** | `.quick_tunnel_url.txt` |

**What it does:**
- Creates a Cloudflare "quick tunnel" (no account needed)
- Exposes `localhost:8765` to the internet
- Writes the tunnel URL to `.quick_tunnel_url.txt`
- **URL changes every restart** (that's why we need NavixyUrlSync)

**How it works:**
```
cloudflared tunnel --url http://localhost:8765
```

**Important:** The tunnel URL is temporary and changes on every restart. This is why the `NavixyUrlSync` service exists - to automatically update GitHub with the new URL.

---

### 3️⃣ NavixyDashboard (Monitoring Dashboard)

| Property | Value |
|----------|-------|
| **Port** | 8766 |
| **Script** | `service\start_dashboard.ps1` |
| **Main File** | `dashboard.py` |
| **Dependencies** | NavixyApi must be running |

**What it does:**
- Provides a web-based monitoring interface
- Shows health status of all 11 system components
- Displays current tunnel URL
- Has quick links to Live Map and Live Data
- Includes "System Reset" button to restart all services

**Access:**
```
http://localhost:8766
```

**Components Monitored:**
1. Python Environment
2. Flask Server Process
3. Cloudflare Tunnel Process
4. API Server Responding
5. Tunnel URL File Exists
6. Tunnel URL Accessible
7. Local Data Endpoint
8. GitHub Pages Status
9. index.html Updated
10. Git Repository Status
11. URL Sync Service

---

### 4️⃣ NavixyUrlSync (GitHub Auto-Sync)

| Property | Value |
|----------|-------|
| **Script** | `service\start_url_sync.ps1` |
| **Dependencies** | NavixyQuickTunnel must be running |
| **Git Repo** | `https://github.com/golanmoyal2023/navixy-live-map` |

**What it does:**
- Monitors the tunnel log for new URLs
- When a new URL is detected:
  1. Updates `.quick_tunnel_url.txt`
  2. Updates `index.html` with new API URL
  3. Commits and pushes to GitHub
  4. GitHub Pages automatically deploys

**This is the KEY service for 100% automation!**

**How it detects URL changes:**
```powershell
# Watches tunnel log file for lines like:
# "https://abc-def-ghi.trycloudflare.com"
```

**Git Configuration (runs as SYSTEM account):**
```powershell
git config --global --add safe.directory "D:\path\to\navixy-live-map"
git config user.email "navixy-service@localhost"
git config user.name "Navixy URL Sync Service"
```

---

## Service Dependencies & Startup Order

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVICE STARTUP ORDER                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   BOOT ──▶ [1] NavixyApi ──┬──▶ [2] NavixyQuickTunnel          │
│                            │         │                          │
│                            │         ▼                          │
│                            │    [4] NavixyUrlSync               │
│                            │                                    │
│                            └──▶ [3] NavixyDashboard             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

| Order | Service | Depends On | Why |
|-------|---------|------------|-----|
| 1 | NavixyApi | None | Must serve data before tunnel can expose it |
| 2 | NavixyQuickTunnel | NavixyApi | Needs API running to tunnel to |
| 3 | NavixyDashboard | NavixyApi | Needs to check API health |
| 4 | NavixyUrlSync | NavixyQuickTunnel | Needs tunnel URL to sync |

---

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           COMPLETE DATA FLOW                              │
└──────────────────────────────────────────────────────────────────────────┘

1. DATA FLOW (Real-time GPS):
   
   Navixy Cloud API ──▶ NavixyApi (Flask) ──▶ Cloudflare Tunnel ──▶ Internet
         │                    │                                         │
         │                    ▼                                         ▼
         │              localhost:8765                        External Users
         │                    │                              (GitHub Pages)
         │                    ▼
         │              Local Browser


2. URL SYNC FLOW (On Restart):

   Tunnel Starts ──▶ New URL Generated ──▶ NavixyUrlSync Detects
                                                    │
                                                    ▼
                                          Updates index.html
                                                    │
                                                    ▼
                                          Git Commit & Push
                                                    │
                                                    ▼
                                          GitHub Pages Updates
                                                    │
                                                    ▼
                                          External Map Works! ✅
```

---

## File Structure

```
navixy-live-map/
├── server.py                    # Main Flask API server
├── dashboard.py                 # Dashboard Flask app
├── index.html                   # Map interface (synced to GitHub)
├── .quick_tunnel_url.txt        # Current tunnel URL (auto-updated)
├── requirements.txt             # Python dependencies
├── .venv/                       # Python virtual environment
│   └── Scripts/
│       └── python.exe           # Use THIS Python for services
│
├── service/                     # Service scripts and configs
│   ├── env.ps1                  # Environment variables (API_HASH)
│   ├── start_server.ps1         # Starts NavixyApi
│   ├── start_quick_tunnel.ps1   # Starts NavixyQuickTunnel
│   ├── start_dashboard.ps1      # Starts NavixyDashboard
│   ├── start_url_sync.ps1       # Starts NavixyUrlSync
│   ├── simulate_restart.ps1     # Test restart without reboot
│   ├── install_all_services.ps1 # Install all 4 services
│   └── logs/                    # Service log files
│       ├── navixyapi_stdout.log
│       ├── navixyapi_stderr.log
│       └── ...
│
├── dashboard/                   # Dashboard UI files
│   ├── templates/
│   │   └── dashboard.html
│   └── static/
│       ├── dashboard.css
│       └── dashboard.js
│
└── REMOTE_SERVER_INSTALL/       # For installing on other machines
    ├── install_all_services.ps1
    └── README.md
```

---

## Configuration Files

### 1. `service\env.ps1` - Environment Variables

```powershell
# CRITICAL: Your Navixy API hash
$env:NAVIXY_API_HASH = "f038d4c96bfc683cdc52337824f7e5f0"
```

**⚠️ Update this file with YOUR API hash before installation!**

### 2. `.quick_tunnel_url.txt` - Current Tunnel URL

This file is **auto-generated** by the tunnel service:
```
https://abc-def-ghi.trycloudflare.com
```

### 3. `index.html` - Map Interface

Contains the API URL that gets updated automatically:
```html
const API_URL = "https://abc-def-ghi.trycloudflare.com/data";
```

---

## Service Management Commands

### View All Services

```powershell
Get-Service -Name "Navixy*" | Format-Table Name, Status, StartType
```

### Start All Services

```powershell
Start-Service -Name "NavixyApi"
Start-Service -Name "NavixyQuickTunnel"
Start-Service -Name "NavixyDashboard"
Start-Service -Name "NavixyUrlSync"
```

### Stop All Services

```powershell
Stop-Service -Name "NavixyApi" -Force
Stop-Service -Name "NavixyQuickTunnel" -Force
Stop-Service -Name "NavixyDashboard" -Force
Stop-Service -Name "NavixyUrlSync" -Force
```

### Restart All Services (Simulate Restart)

```powershell
cd "D:\path\to\navixy-live-map\service"
.\simulate_restart.ps1
```

### Check Service Logs

```powershell
# View recent API logs
Get-Content "service\logs\navixyapi_stdout.log" -Tail 50

# View tunnel logs (check for URL)
Get-Content "service\logs\navixyquicktunnel_stdout.log" -Tail 50

# View URL sync logs
Get-Content "service\logs\navixyurlsync_stdout.log" -Tail 50
```

### Using NSSM for Service Management

```powershell
$nssm = "C:\ProgramData\chocolatey\bin\nssm.exe"

# View service config
& $nssm get NavixyApi Application
& $nssm get NavixyApi AppParameters

# Edit service interactively
& $nssm edit NavixyApi

# View service status
& $nssm status NavixyApi
```

---

## Troubleshooting Guide

### Problem: Service Won't Start / Stays "Paused"

**Cause:** Dependencies not met or script error

**Solution:**
```powershell
# 1. Check dependencies - start in order
Start-Service NavixyApi
Start-Sleep 5
Start-Service NavixyQuickTunnel
Start-Sleep 5
Start-Service NavixyDashboard
Start-Service NavixyUrlSync

# 2. Check logs for errors
Get-Content "service\logs\navixyapi_stderr.log" -Tail 20
```

---

### Problem: "NAVIXY_API_HASH is not set"

**Cause:** Environment variable not loaded

**Solution:**
1. Check `service\env.ps1` has correct hash
2. Ensure `start_server.ps1` sources `env.ps1`:
```powershell
. "$PSScriptRoot\env.ps1"
```

---

### Problem: Tunnel URL Not Updating on GitHub

**Cause:** Git permissions issue (service runs as SYSTEM)

**Solution:** Add to `start_url_sync.ps1`:
```powershell
git config --global --add safe.directory "D:\path\to\navixy-live-map"
git config user.email "navixy-service@localhost"
git config user.name "Navixy URL Sync Service"
```

---

### Problem: Dashboard Shows 100% But External Fails

**Cause:** Old tunnel URL in GitHub Pages

**Solution:**
1. Check current tunnel URL: `Get-Content .quick_tunnel_url.txt`
2. Check if NavixyUrlSync is running
3. Manually trigger sync:
```powershell
.\service\start_url_sync.ps1
```

---

### Problem: "Access Denied" When Managing Services

**Cause:** Not running as Administrator

**Solution:** Right-click PowerShell → "Run as Administrator"

---

### Problem: Port Already in Use

**Cause:** Another process using 8765 or 8766

**Solution:**
```powershell
# Find what's using port 8765
netstat -ano | findstr ":8765"

# Kill process by PID
taskkill /PID <pid> /F
```

---

## Installation Steps

### Prerequisites

1. **Python 3.x** with virtual environment
2. **NSSM** (Non-Sucking Service Manager)
   ```powershell
   choco install nssm
   # or
   winget install --id Nssm.Nssm -e
   ```
3. **cloudflared** CLI
   ```powershell
   winget install --id Cloudflare.cloudflared -e
   ```
4. **Git** (for URL sync)

### Installation Command

```powershell
# Navigate to install folder
cd "D:\path\to\navixy-live-map\REMOTE_SERVER_INSTALL"

# Run as Administrator
.\install_all_services.ps1 -InstallPath "D:\path\to\navixy-live-map"
```

### Verify Installation

```powershell
# Check all services exist and are running
Get-Service -Name "Navixy*"

# Open dashboard
Start-Process "http://localhost:8766"
```

---

## Quick Reference Card

| Service | Port | Script | Log |
|---------|------|--------|-----|
| NavixyApi | 8765 | `start_server.ps1` | `navixyapi_*.log` |
| NavixyQuickTunnel | - | `start_quick_tunnel.ps1` | `navixyquicktunnel_*.log` |
| NavixyDashboard | 8766 | `start_dashboard.ps1` | `navixydashboard_*.log` |
| NavixyUrlSync | - | `start_url_sync.ps1` | `navixyurlsync_*.log` |

| URL | Purpose |
|-----|---------|
| `http://localhost:8765` | Local map |
| `http://localhost:8765/data` | API data |
| `http://localhost:8766` | Dashboard |
| `https://golanmoyal2023.github.io/navixy-live-map/` | External map |

---

## Contact & Support

For issues with this setup, review:
1. This guide
2. Service logs in `service\logs\`
3. `FINAL_SETUP_SUMMARY.md` (if available)
4. `SESSION_LOG_*.md` files for historical context

---

*Document created: 2026-02-03*
*System: Navixy Live Map 4-Service Architecture*
