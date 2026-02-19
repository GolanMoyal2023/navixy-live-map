# Install All Services Including Dashboard
# Installs NavixyApi, NavixyBroker, NavixyTunnel, NavixyDashboard (server + broker + tunnel + dashboard from repo/branch)

$ErrorActionPreference = "Stop"

$nssm = "C:\Tools\nssm\nssm.exe"
# Repo root from script path - services use same broker/server logic as branch
$root = Split-Path -Parent $PSScriptRoot
$serverScript = "$root\service\start_server.ps1"
$tunnelScript = "$root\service\start_tunnel.ps1"
$brokerScript = "$root\service\start_broker.ps1"
$dashboardScript = "$root\service\start_dashboard.ps1"
$openDashboardScript = "$root\service\open_dashboard.ps1"

if (-not (Test-Path $nssm)) { throw "NSSM not found at $nssm" }
if (-not (Test-Path $serverScript)) { throw "Missing $serverScript" }
if (-not (Test-Path $tunnelScript)) { throw "Missing $tunnelScript" }
if (-not (Test-Path $brokerScript)) { throw "Missing $brokerScript" }
if (-not (Test-Path $dashboardScript)) { throw "Missing $dashboardScript" }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installing Navixy Services (API + Broker + Tunnel + Dashboard)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Repo root: $root" -ForegroundColor Gray
Write-Host ""

# Remove existing services if they exist
Write-Host "Removing existing services..." -ForegroundColor Yellow
& $nssm stop NavixyApi | Out-Null
& $nssm remove NavixyApi confirm | Out-Null
& $nssm stop NavixyBroker | Out-Null
& $nssm remove NavixyBroker confirm | Out-Null
& $nssm stop NavixyTunnel | Out-Null
& $nssm remove NavixyTunnel confirm | Out-Null
& $nssm stop NavixyDashboard | Out-Null
& $nssm remove NavixyDashboard confirm | Out-Null
Start-Sleep -Seconds 2

# Install NavixyApi service
Write-Host "Installing NavixyApi service..." -ForegroundColor Green
& $nssm install NavixyApi "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$serverScript`""
& $nssm set NavixyApi AppDirectory $root
& $nssm set NavixyApi DisplayName "Navixy API Server"
& $nssm set NavixyApi Description "Navixy Live Map API Server (Flask) - port 8767"
& $nssm set NavixyApi Start SERVICE_AUTO_START
& $nssm set NavixyApi AppRestartDelay 5000
& $nssm set NavixyApi AppExit Default Restart

# Install NavixyBroker service (Teltonika broker - same logic as branch)
Write-Host "Installing NavixyBroker service..." -ForegroundColor Green
& $nssm install NavixyBroker "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$brokerScript`""
& $nssm set NavixyBroker AppDirectory $root
& $nssm set NavixyBroker DisplayName "Navixy Teltonika Broker"
& $nssm set NavixyBroker Description "Teltonika broker TCP 15027, HTTP 8768 - BLE, 60s logic"
& $nssm set NavixyBroker Start SERVICE_AUTO_START
& $nssm set NavixyBroker AppRestartDelay 5000
& $nssm set NavixyBroker AppExit Default Restart

# Install NavixyTunnel service
Write-Host "Installing NavixyTunnel service..." -ForegroundColor Green
& $nssm install NavixyTunnel "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$tunnelScript`""
& $nssm set NavixyTunnel AppDirectory $root
& $nssm set NavixyTunnel DisplayName "Navixy Cloudflare Tunnel"
& $nssm set NavixyTunnel Description "Cloudflare named tunnel for Navixy Live Map"
& $nssm set NavixyTunnel Start SERVICE_AUTO_START
& $nssm set NavixyTunnel AppRestartDelay 5000
& $nssm set NavixyTunnel AppExit Default Restart
& $nssm set NavixyTunnel DependOnService NavixyApi

# Install NavixyDashboard service
Write-Host "Installing NavixyDashboard service..." -ForegroundColor Green
& $nssm install NavixyDashboard "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$dashboardScript`""
& $nssm set NavixyDashboard AppDirectory $root
& $nssm set NavixyDashboard DisplayName "Navixy System Dashboard"
& $nssm set NavixyDashboard Description "Dashboard and Debug Interface for Navixy System"
& $nssm set NavixyDashboard Start SERVICE_AUTO_START
& $nssm set NavixyDashboard AppRestartDelay 5000
& $nssm set NavixyDashboard AppExit Default Restart
& $nssm set NavixyDashboard DependOnService NavixyApi

# Start services in order
Write-Host ""
Write-Host "Starting services..." -ForegroundColor Yellow
& $nssm start NavixyApi
Start-Sleep -Seconds 2
& $nssm start NavixyBroker
Start-Sleep -Seconds 2
& $nssm start NavixyTunnel
Start-Sleep -Seconds 2
& $nssm start NavixyDashboard
Start-Sleep -Seconds 5

# Open dashboard in browser
Write-Host ""
Write-Host "Opening dashboard in browser..." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $openDashboardScript

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Services Installed and Started!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services:" -ForegroundColor Yellow
Write-Host "  - NavixyApi (8767)" -ForegroundColor White
Write-Host "  - NavixyBroker (15027, 8768)" -ForegroundColor White
Write-Host "  - NavixyTunnel (Cloudflare)" -ForegroundColor White
Write-Host "  - NavixyDashboard (8766)" -ForegroundColor White
Write-Host ""
Write-Host "Dashboard: http://127.0.0.1:8766" -ForegroundColor Cyan
Write-Host "All services use repo/branch logic and start automatically on reboot." -ForegroundColor Green
Write-Host ""
