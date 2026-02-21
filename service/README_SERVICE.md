# Navixy Live Map – Service setup (NSSM)

All services use the **repo root** where the script lives (branch-safe: same broker/server logic as branch).

## 1) Install NSSM
- Download: https://nssm.cc/download
- Extract and place `nssm.exe` in a known folder (e.g. `C:\Tools\nssm\nssm.exe`)

## 2) Install all services (recommended)
From repo root (e.g. `D:\2Plus\Services\navixy-live-map`), run as Administrator:
```powershell
.\service\install_services.ps1
```
Installs: **NavixyApi** (8767), **NavixyBroker** (15027, 8768), **NavixyTunnel** (Cloudflare).

With dashboard:
```powershell
.\service\install_services_with_dashboard.ps1
```
Adds **NavixyDashboard** (8766). All paths are taken from the script location (repo/branch).

## 3) Services (server + broker + tunnel from branch)
| Service       | Script             | Role |
|---------------|--------------------|------|
| NavixyApi     | start_server.ps1   | Navixy API – port 8767 |
| NavixyBroker  | start_broker.ps1   | Teltonika broker – TCP 15027, HTTP 8768 |
| NavixyTunnel  | start_tunnel.ps1   | Cloudflare named tunnel |
| NavixyDashboard | start_dashboard.ps1 | Dashboard – port 8766 |

## 4) Start / stop (NSSM)
- Start: `nssm start NavixyApi` then `nssm start NavixyBroker` then `nssm start NavixyTunnel`
- Stop: `nssm stop NavixyTunnel` then `nssm stop NavixyBroker` then `nssm stop NavixyApi`

## 5) Notes
- Set **NAVIXY_API_HASH** and **PORT** in `service\env.ps1` (PORT=8767 for map).
- Repo root is derived from `service\` path so the same code (branch) runs as service.
