# Navixy Live Map - Remote Server Installation Package

## Quick Install

1. **Copy this entire folder** to your server
2. **Run as Administrator:**
   ```powershell
   .\install_all_services.ps1 -InstallPath "D:\Path\To\navixy-live-map"
   ```

## Prerequisites

| Requirement | Install Command |
|-------------|-----------------|
| **NSSM** | `winget install --id Nssm.Nssm -e` or `choco install nssm` |
| **cloudflared** | `winget install --id Cloudflare.cloudflared -e` |
| **Python 3.x** | `winget install --id Python.Python.3.12 -e` |
| **Git** | `winget install --id Git.Git -e` |

## What Gets Installed

| Service | Description | Port |
|---------|-------------|------|
| **NavixyApi** | Flask API server | 8765 |
| **NavixyQuickTunnel** | Cloudflare tunnel | - |
| **NavixyDashboard** | System monitoring | 8766 |
| **NavixyUrlSync** | Auto GitHub sync | - |

## Files Required in Target Location

```
navixy-live-map/
├── .venv/                    # Python virtual environment
├── server.py                 # API server
├── dashboard.py              # Dashboard server
├── index.html                # Map HTML (for GitHub)
├── .quick_tunnel_url.txt     # Tunnel URL storage
├── dashboard/                # Dashboard templates & static
│   ├── templates/
│   └── static/
└── service/                  # Service scripts
    ├── env.ps1
    ├── start_server.ps1
    ├── start_quick_tunnel.ps1
    ├── start_dashboard.ps1
    ├── start_url_sync.ps1
    └── logs/
```

## After Installation

1. **Check Dashboard:** http://localhost:8766
2. **Check API:** http://localhost:8765/data
3. **External Map:** https://golanmoyal2023.github.io/navixy-live-map/

## Service Management

```powershell
# Check status
Get-Service NavixyApi, NavixyQuickTunnel, NavixyDashboard, NavixyUrlSync

# Stop all
Stop-Service NavixyApi, NavixyQuickTunnel, NavixyDashboard, NavixyUrlSync

# Start all
Start-Service NavixyApi, NavixyQuickTunnel, NavixyDashboard, NavixyUrlSync

# Restart all (simulate reboot)
.\simulate_restart.ps1
```

## Troubleshooting

**Logs location:** `service\logs\`

| Log File | Content |
|----------|---------|
| `navixyapi_stdout.log` | API server output |
| `navixyquicktunnel_stderr.log` | Tunnel output (URL here) |
| `url_sync.log` | URL sync activity |

---
**Generated:** 2026-02-02
