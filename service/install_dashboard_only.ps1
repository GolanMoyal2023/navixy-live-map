# Install Dashboard Service Only (Third Service)
# Adds NavixyDashboard without touching existing services

$ErrorActionPreference = "Stop"

$nssm = "C:\Tools\nssm\nssm.exe"
$root = "D:\New_Recovery\2Plus\navixy-live-map"
$dashboardScript = "$root\service\start_dashboard.ps1"
$openDashboardScript = "$root\service\open_dashboard.ps1"

if (-not (Test-Path $nssm)) {
    throw "NSSM not found at $nssm"
}

if (-not (Test-Path $dashboardScript)) {
    throw "Missing $dashboardScript"
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installing Dashboard Service (3rd)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Existing services:" -ForegroundColor Yellow
Write-Host "  1. NavixyApi         - Running" -ForegroundColor Green
Write-Host "  2. NavixyQuickTunnel - Running" -ForegroundColor Green
Write-Host "  3. NavixyDashboard   - Installing..." -ForegroundColor Yellow
Write-Host ""

# Remove existing dashboard service if exists (ignore errors if doesn't exist)
try { & $nssm stop NavixyDashboard 2>&1 | Out-Null } catch {}
try { & $nssm remove NavixyDashboard confirm 2>&1 | Out-Null } catch {}
Start-Sleep -Seconds 2

# Install NavixyDashboard service
Write-Host "Installing NavixyDashboard service..." -ForegroundColor Green
& $nssm install NavixyDashboard "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$dashboardScript`""
& $nssm set NavixyDashboard AppDirectory $root
& $nssm set NavixyDashboard DisplayName "Navixy System Dashboard"
& $nssm set NavixyDashboard Description "Dashboard and Debug Interface for Navixy System (Port 8766)"
& $nssm set NavixyDashboard Start SERVICE_AUTO_START
& $nssm set NavixyDashboard AppRestartDelay 5000
& $nssm set NavixyDashboard AppExit Default Restart
# Dashboard depends on API
& $nssm set NavixyDashboard DependOnService NavixyApi

Write-Host "✅ Service installed!" -ForegroundColor Green
Write-Host ""

# Start dashboard service
Write-Host "Starting NavixyDashboard service..." -ForegroundColor Yellow
& $nssm start NavixyDashboard
Start-Sleep -Seconds 5

# Open dashboard in browser
Write-Host ""
Write-Host "Opening dashboard in browser..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
Start-Process "http://127.0.0.1:8766"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ Dashboard Service Installed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "All 3 Services:" -ForegroundColor Yellow
Get-Service -Name "NavixyApi","NavixyQuickTunnel","NavixyDashboard" -ErrorAction SilentlyContinue | Format-Table -AutoSize Name, Status, StartType
Write-Host ""
Write-Host "Dashboard: http://127.0.0.1:8766" -ForegroundColor Cyan
Write-Host ""
Write-Host "All services will start automatically on reboot!" -ForegroundColor Green
Write-Host ""
