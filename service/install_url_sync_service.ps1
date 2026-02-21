# Install URL Sync Service (4th Service)
# This service automatically syncs tunnel URL changes to GitHub
# NO human intervention required!

$ErrorActionPreference = "Continue"

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "Installing URL Sync Service (4th)" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

# Check for admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "Running as Administrator" -ForegroundColor Green
Write-Host ""

$root = Split-Path -Parent $PSScriptRoot
# Find NSSM - check multiple locations
$nssmLocations = @(
    "$PSScriptRoot\nssm.exe",
    "C:\ProgramData\chocolatey\bin\nssm.exe",
    "C:\nssm\nssm.exe",
    "C:\Tools\nssm.exe"
)
$nssm = $null
foreach ($loc in $nssmLocations) {
    if (Test-Path $loc) {
        $nssm = $loc
        break
    }
}
if (-not $nssm) {
    # Try PATH
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd) { $nssm = $nssmCmd.Source }
}
if (-not $nssm) {
    Write-Host "ERROR: NSSM not found! Please install NSSM." -ForegroundColor Red
    exit 1
}
Write-Host "Using NSSM: $nssm" -ForegroundColor Gray
$serviceName = "NavixyUrlSync"

# Check existing services
Write-Host "Current services:" -ForegroundColor Yellow
$services = @("NavixyApi", "NavixyQuickTunnel", "NavixyDashboard", "NavixyUrlSync")
foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "  $svc - $($service.Status)" -ForegroundColor $(if ($service.Status -eq "Running") { "Green" } else { "Yellow" })
    } else {
        Write-Host "  $svc - Not installed" -ForegroundColor Gray
    }
}
Write-Host ""

# Stop and remove existing service (ignore errors if service doesn't exist)
Write-Host "Installing $serviceName..." -ForegroundColor Yellow
$null = & $nssm stop $serviceName 2>&1
$null = & $nssm remove $serviceName confirm 2>&1
Start-Sleep -Seconds 1

# Install service
$scriptPath = "$PSScriptRoot\start_url_sync.ps1"
& $nssm install $serviceName powershell.exe "-ExecutionPolicy Bypass -File `"$scriptPath`""
& $nssm set $serviceName DisplayName "Navixy URL Sync (GitHub)"
& $nssm set $serviceName Description "Automatically syncs tunnel URL changes to GitHub Pages"
& $nssm set $serviceName Start SERVICE_AUTO_START
& $nssm set $serviceName AppDirectory $root

# Set service to depend on NavixyQuickTunnel (start after tunnel)
& $nssm set $serviceName DependOnService NavixyQuickTunnel

# Configure logging
$logDir = "$root\service\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
& $nssm set $serviceName AppStdout "$logDir\url_sync_stdout.log"
& $nssm set $serviceName AppStderr "$logDir\url_sync_stderr.log"
& $nssm set $serviceName AppRotateFiles 1
& $nssm set $serviceName AppRotateBytes 1048576

Write-Host "Service installed!" -ForegroundColor Green
Write-Host ""

# Start the service
Write-Host "Starting service..." -ForegroundColor Yellow
Start-Service -Name $serviceName
Start-Sleep -Seconds 2

$service = Get-Service -Name $serviceName
Write-Host "Service status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq "Running") { "Green" } else { "Red" })
Write-Host ""

# Show all 4 services
Write-Host "========================================"  -ForegroundColor Green
Write-Host "ALL 4 SERVICES:" -ForegroundColor Green
Write-Host "========================================"  -ForegroundColor Green
Write-Host ""

$allServices = @("NavixyApi", "NavixyQuickTunnel", "NavixyDashboard", "NavixyUrlSync")
foreach ($svc in $allServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host "  $svc - Running (Automatic)" -ForegroundColor Green
    } else {
        Write-Host "  $svc - $($service.Status)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "100% AUTOMATED RESTART FLOW:" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Computer boots" -ForegroundColor White
Write-Host "  2. NavixyApi starts (serves data on :8765)" -ForegroundColor White
Write-Host "  3. NavixyQuickTunnel starts (creates tunnel)" -ForegroundColor White
Write-Host "  4. NavixyDashboard starts (dashboard on :8766)" -ForegroundColor White
Write-Host "  5. NavixyUrlSync starts (waits for tunnel)" -ForegroundColor White
Write-Host "     -> Detects new URL in logs" -ForegroundColor Gray
Write-Host "     -> Updates index.html" -ForegroundColor Gray
Write-Host "     -> Pushes to GitHub automatically" -ForegroundColor Gray
Write-Host "  6. External map works!" -ForegroundColor Green
Write-Host ""
Write-Host "NO HUMAN INTERVENTION REQUIRED!" -ForegroundColor Green
Write-Host ""
