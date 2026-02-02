# Navixy Live Map

Real-time vehicle tracking map visualization system with Cloudflare tunnel for external access.

## Quick Links

| Access | URL |
|--------|-----|
| **Dashboard** | http://localhost:8766 |
| **Local API** | http://localhost:8765/data |
| **External Map** | https://golanmoyal2023.github.io/navixy-live-map/ |

## Project Structure

```
navixy-live-map/
├── server.py                   # Flask API server (port 8765)
├── dashboard.py                # Dashboard server (port 8766)
├── index.html                  # Main map HTML (GitHub Pages)
├── index.local.html            # Local testing version
├── requirements.txt            # Python dependencies
├── .quick_tunnel_url.txt       # Current tunnel URL
│
├── dashboard/                  # Dashboard UI
│   ├── templates/
│   └── static/
│
├── service/                    # Windows service scripts
│   ├── env.ps1                 # Environment variables
│   ├── start_server.ps1        # API server startup
│   ├── start_dashboard.ps1     # Dashboard startup
│   ├── start_quick_tunnel.ps1  # Tunnel startup
│   ├── start_url_sync.ps1      # URL sync service
│   ├── simulate_restart.ps1    # Test restart flow
│   └── logs/                   # Service logs
│
├── overlays/                   # Map overlay files
├── .cloudflared/               # Tunnel configuration
├── .venv/                      # Python virtual environment
│
├── REMOTE_SERVER_INSTALL/      # Remote deployment package
│   ├── install_all_services.ps1
│   └── README.md
│
└── archive/                    # Archived obsolete scripts
    └── obsolete_scripts/
```

## Windows Services

| Service | Description | Startup |
|---------|-------------|---------|
| **NavixyApi** | Flask API server | Automatic |
| **NavixyQuickTunnel** | Cloudflare tunnel | Automatic |
| **NavixyDashboard** | System monitoring | Automatic |
| **NavixyUrlSync** | GitHub URL sync | Automatic |

## Installation

### Install All 4 Services (Admin PowerShell)

```powershell
cd "D:\New_Recovery\2Plus\navixy-live-map\service"
.\install_all_services.ps1
```

### Service Management

```powershell
# Check status
Get-Service NavixyApi, NavixyQuickTunnel, NavixyDashboard, NavixyUrlSync

# Restart all (simulate reboot)
.\service\simulate_restart.ps1
```

## Features

- ✅ Real-time vehicle tracking
- ✅ Auto-start on boot
- ✅ Cloudflare tunnel (no DNS needed)
- ✅ Auto URL sync to GitHub
- ✅ System health dashboard
- ✅ 11 component monitoring

## Related Project

**ELAL POC** - Main project documentation
- Location: `D:\New_Recovery\2Plus\ELAL POC`

---
**Last Updated:** 2026-02-02
