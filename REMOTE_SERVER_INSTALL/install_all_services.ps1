#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Navixy Live Map - Complete 4-Service Installation Package
    
.DESCRIPTION
    This script installs all 4 Windows services required for the Navixy Live Map system:
    1. NavixyApi - Flask API server (port 8765)
    2. NavixyQuickTunnel - Cloudflare tunnel for external access
    3. NavixyDashboard - System monitoring dashboard (port 8766)
    4. NavixyUrlSync - Automatic URL sync to GitHub
    
.NOTES
    - Run as Administrator
    - Requires NSSM (Non-Sucking Service Manager)
    - Requires Python 3.x with virtual environment
    - Requires cloudflared CLI
    - Requires Git for URL sync
    
.PARAMETER InstallPath
    The path where navixy-live-map is installed (default: D:\New_Recovery\2Plus\navixy-live-map)
    
.EXAMPLE
    .\install_all_services.ps1
    .\install_all_services.ps1 -InstallPath "E:\MyProject\navixy-live-map"
#>

param(
    [string]$InstallPath = "D:\New_Recovery\2Plus\navixy-live-map"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  NAVIXY LIVE MAP - 4 SERVICE INSTALLATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Install Path: $InstallPath" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# PREREQUISITE CHECKS
# ============================================================

Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check Admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Run as Administrator!" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Running as Administrator" -ForegroundColor Green

# Check Install Path
if (-not (Test-Path $InstallPath)) {
    Write-Host "ERROR: Install path not found: $InstallPath" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Install path exists" -ForegroundColor Green

# Check Python venv
$python = Join-Path $InstallPath ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    Write-Host "ERROR: Python venv not found at: $python" -ForegroundColor Red
    Write-Host "       Create venv: python -m venv .venv" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Python venv found" -ForegroundColor Green

# Find NSSM
$nssmLocations = @(
    "C:\ProgramData\chocolatey\bin\nssm.exe",
    "C:\nssm\nssm.exe",
    "C:\Tools\nssm.exe",
    "C:\Tools\nssm\nssm.exe",
    "$InstallPath\service\nssm.exe"
)
$nssm = $null
foreach ($loc in $nssmLocations) {
    if (Test-Path $loc) {
        $nssm = $loc
        break
    }
}
if (-not $nssm) {
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd) { $nssm = $nssmCmd.Source }
}
if (-not $nssm) {
    Write-Host "ERROR: NSSM not found!" -ForegroundColor Red
    Write-Host "       Install: winget install --id Nssm.Nssm -e" -ForegroundColor Yellow
    Write-Host "       Or:      choco install nssm" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] NSSM found: $nssm" -ForegroundColor Green

# Check cloudflared
$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
    Write-Host "ERROR: cloudflared not found!" -ForegroundColor Red
    Write-Host "       Install: winget install --id Cloudflare.cloudflared -e" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] cloudflared found" -ForegroundColor Green

# Check Git
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Host "WARNING: Git not found - URL sync to GitHub won't work" -ForegroundColor Yellow
} else {
    Write-Host "  [OK] Git found" -ForegroundColor Green
}

Write-Host ""
Write-Host "All prerequisites satisfied!" -ForegroundColor Green
Write-Host ""

# ============================================================
# SERVICE DEFINITIONS
# ============================================================

$services = @(
    @{
        Name = "NavixyApi"
        DisplayName = "Navixy API Server"
        Description = "Flask API server for Navixy Live Map (port 8765)"
        Script = "start_server.ps1"
        DependsOn = $null
    },
    @{
        Name = "NavixyQuickTunnel"
        DisplayName = "Navixy Quick Tunnel (Cloudflare)"
        Description = "Cloudflare tunnel for external access"
        Script = "start_quick_tunnel.ps1"
        DependsOn = "NavixyApi"
    },
    @{
        Name = "NavixyDashboard"
        DisplayName = "Navixy System Dashboard"
        Description = "System monitoring dashboard (port 8766)"
        Script = "start_dashboard.ps1"
        DependsOn = "NavixyApi"
    },
    @{
        Name = "NavixyUrlSync"
        DisplayName = "Navixy URL Sync (GitHub)"
        Description = "Automatically syncs tunnel URL changes to GitHub"
        Script = "start_url_sync.ps1"
        DependsOn = "NavixyQuickTunnel"
    }
)

# ============================================================
# CREATE LOG DIRECTORY
# ============================================================

$logDir = Join-Path $InstallPath "service\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-Host "Created log directory: $logDir" -ForegroundColor Gray
}

# ============================================================
# INSTALL SERVICES
# ============================================================

Write-Host "Installing services..." -ForegroundColor Yellow
Write-Host ""

foreach ($svc in $services) {
    Write-Host "Installing $($svc.Name)..." -ForegroundColor Cyan
    
    $scriptPath = Join-Path $InstallPath "service\$($svc.Script)"
    if (-not (Test-Path $scriptPath)) {
        Write-Host "  WARNING: Script not found: $scriptPath" -ForegroundColor Yellow
        continue
    }
    
    # Stop and remove existing service
    $null = & $nssm stop $svc.Name 2>&1
    Start-Sleep -Milliseconds 500
    $null = & $nssm remove $svc.Name confirm 2>&1
    Start-Sleep -Milliseconds 500
    
    # Install service
    & $nssm install $svc.Name powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    & $nssm set $svc.Name DisplayName $svc.DisplayName
    & $nssm set $svc.Name Description $svc.Description
    & $nssm set $svc.Name Start SERVICE_AUTO_START
    & $nssm set $svc.Name AppDirectory $InstallPath
    
    # Set dependency if specified
    if ($svc.DependsOn) {
        & $nssm set $svc.Name DependOnService $svc.DependsOn
    }
    
    # Configure logging
    & $nssm set $svc.Name AppStdout "$logDir\$($svc.Name.ToLower())_stdout.log"
    & $nssm set $svc.Name AppStderr "$logDir\$($svc.Name.ToLower())_stderr.log"
    & $nssm set $svc.Name AppRotateFiles 1
    & $nssm set $svc.Name AppRotateBytes 1048576
    
    Write-Host "  [OK] $($svc.Name) installed" -ForegroundColor Green
}

Write-Host ""

# ============================================================
# START SERVICES
# ============================================================

Write-Host "Starting services..." -ForegroundColor Yellow
Write-Host ""

foreach ($svc in $services) {
    Write-Host "Starting $($svc.Name)..." -ForegroundColor Gray -NoNewline
    Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host " Running" -ForegroundColor Green
    } else {
        Write-Host " $($service.Status)" -ForegroundColor Yellow
    }
}

Write-Host ""

# ============================================================
# FINAL STATUS
# ============================================================

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Service Status:" -ForegroundColor Cyan
foreach ($svc in $services) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    $status = if ($service) { $service.Status } else { "Not Found" }
    $color = if ($status -eq "Running") { "Green" } elseif ($status -eq "Stopped") { "Yellow" } else { "Red" }
    Write-Host "  $($svc.Name) - $status" -ForegroundColor $color
}

Write-Host ""
Write-Host "Quick Access:" -ForegroundColor Cyan
Write-Host "  Dashboard:    http://localhost:8766" -ForegroundColor White
Write-Host "  Local API:    http://localhost:8765/data" -ForegroundColor White
Write-Host "  External Map: https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
Write-Host ""
Write-Host "Logs: $logDir" -ForegroundColor Gray
Write-Host ""

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AUTOMATED RESTART FLOW:" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Computer boots" -ForegroundColor White
Write-Host "  2. NavixyApi starts (serves data on :8765)" -ForegroundColor White
Write-Host "  3. NavixyQuickTunnel starts (creates tunnel)" -ForegroundColor White
Write-Host "  4. NavixyDashboard starts (dashboard on :8766)" -ForegroundColor White
Write-Host "  5. NavixyUrlSync starts (auto-syncs URL to GitHub)" -ForegroundColor White
Write-Host "  6. External map works - NO HUMAN INTERVENTION!" -ForegroundColor Green
Write-Host ""
