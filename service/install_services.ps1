$ErrorActionPreference = "Stop"

$nssm = "C:\Tools\nssm\nssm.exe"
# Use repo root from this script (branch-safe: same repo where install script lives)
$root = Split-Path -Parent $PSScriptRoot
$serverScript = "$root\service\start_server.ps1"
$tunnelScript = "$root\service\start_tunnel.ps1"
$brokerScript = "$root\service\start_broker.ps1"

if (-not (Test-Path $nssm)) {
    throw "NSSM not found at $nssm"
}

if (-not (Test-Path $serverScript)) { throw "Missing $serverScript" }
if (-not (Test-Path $tunnelScript)) { throw "Missing $tunnelScript" }
if (-not (Test-Path $brokerScript)) { throw "Missing $brokerScript" }

Write-Host "Repo root: $root" -ForegroundColor Gray

# Remove existing services if they exist
& $nssm stop NavixyApi | Out-Null
& $nssm remove NavixyApi confirm | Out-Null
& $nssm stop NavixyTunnel | Out-Null
& $nssm remove NavixyTunnel confirm | Out-Null
& $nssm stop NavixyBroker | Out-Null
& $nssm remove NavixyBroker confirm | Out-Null
Start-Sleep -Seconds 2

# Install NavixyApi service (server - Navixy API for map)
& $nssm install NavixyApi "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$serverScript`""
& $nssm set NavixyApi AppDirectory $root
& $nssm set NavixyApi DisplayName "Navixy API Server"
& $nssm set NavixyApi Description "Navixy Live Map API (Flask) - port 8767"
& $nssm set NavixyApi Start SERVICE_AUTO_START
& $nssm set NavixyApi AppRestartDelay 5000
& $nssm set NavixyApi AppExit Default Restart

# Install NavixyBroker service (Teltonika broker - TCP 15027, HTTP 8768)
& $nssm install NavixyBroker "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$brokerScript`""
& $nssm set NavixyBroker AppDirectory $root
& $nssm set NavixyBroker DisplayName "Navixy Teltonika Broker"
& $nssm set NavixyBroker Description "Teltonika TCP/HTTP broker - BLE, 60s logic, /data on 8768"
& $nssm set NavixyBroker Start SERVICE_AUTO_START
& $nssm set NavixyBroker AppRestartDelay 5000
& $nssm set NavixyBroker AppExit Default Restart

# Install NavixyTunnel service (Cloudflare)
& $nssm install NavixyTunnel "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$tunnelScript`""
& $nssm set NavixyTunnel AppDirectory $root
& $nssm set NavixyTunnel DisplayName "Navixy Cloudflare Tunnel"
& $nssm set NavixyTunnel Description "Cloudflare named tunnel for Navixy Live Map"
& $nssm set NavixyTunnel Start SERVICE_AUTO_START
& $nssm set NavixyTunnel AppRestartDelay 5000
& $nssm set NavixyTunnel AppExit Default Restart
& $nssm set NavixyTunnel DependOnService NavixyApi

# Start services: API first, then broker, then tunnel
& $nssm start NavixyApi
Start-Sleep -Seconds 2
& $nssm start NavixyBroker
Start-Sleep -Seconds 2
& $nssm start NavixyTunnel

Write-Host "Services installed and started: NavixyApi (8767), NavixyBroker (15027/8768), NavixyTunnel"
