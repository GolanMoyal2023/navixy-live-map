Service setup overview (NSSM)

1) Install NSSM
- Download: https://nssm.cc/download
- Extract and place nssm.exe in a known folder (e.g. C:\Tools\nssm\nssm.exe)

2) Create service for API server
- Command (PowerShell, run as Administrator):
  C:\Tools\nssm\nssm.exe install NavixyApi
- In NSSM UI:
  - Application Path: powershell.exe
  - Startup directory: D:\New_Recovery\2Plus\navixy-live-map
  - Arguments: -NoProfile -ExecutionPolicy Bypass -File "D:\New_Recovery\2Plus\navixy-live-map\service\start_server.ps1"

3) Create service for Tunnel
- Command (PowerShell, run as Administrator):
  C:\Tools\nssm\nssm.exe install NavixyTunnel
- In NSSM UI:
  - Application Path: powershell.exe
  - Startup directory: D:\New_Recovery\2Plus\navixy-live-map
  - Arguments: -NoProfile -ExecutionPolicy Bypass -File "D:\New_Recovery\2Plus\navixy-live-map\service\start_tunnel.ps1"

4) Start services
- C:\Tools\nssm\nssm.exe start NavixyApi
- C:\Tools\nssm\nssm.exe start NavixyTunnel

5) Stop services
- C:\Tools\nssm\nssm.exe stop NavixyTunnel
- C:\Tools\nssm\nssm.exe stop NavixyApi

Notes
- Update the NAVIXY_API_HASH in env.ps1 before installation on another PC.
- If you change port, update env.ps1.
