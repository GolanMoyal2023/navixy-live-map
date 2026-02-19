# Navixy Live Map - Failure / Maintenance Recovery
# Use when the server is down, after maintenance, or to verify and restart services.
# Run from repo: .\service\recovery.ps1   or   .\service\recovery.ps1 -VerifyOnly
# Optional: -VerifyOnly (only health check, no restart), -RestartServicesOnly (restart Windows services only, no start_all)

param(
    [switch]$VerifyOnly,
    [switch]$RestartServicesOnly
)

$ErrorActionPreference = "Continue"
$root = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }
$root = $root.TrimEnd("\")
$logDir = Join-Path $root "service\logs"
$logFile = Join-Path $logDir "recovery.log"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Msg"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
    $color = switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } default { "Gray" } }
    Write-Host $line -ForegroundColor $color
}

function Test-Endpoint {
    param([string]$Url, [int]$TimeoutSec = 5)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return $r.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Get-ProcessIdsOnPort {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $conn) { return @() }
    $conn | ForEach-Object { $_.OwningProcess } | Select-Object -Unique
}

function Stop-ProcessesOnPorts {
    param([int[]]$Ports)
    foreach ($p in $Ports) {
        $pids = Get-ProcessIdsOnPort -Port $p
        foreach ($id in $pids) {
            if ($id -gt 0) {
                Write-Log "Stopping process $id on port $p" "WARN"
                Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            }
        }
    }
}

# --- Health check (ports 8767 Navixy API, 8768 Broker, 8080 Map)
$endpoints = @(
    @{ Name = "Navixy API (8767)"; Url = "http://127.0.0.1:8767/data" },
    @{ Name = "Broker (8768)";     Url = "http://127.0.0.1:8768/" },
    @{ Name = "Map UI (8080)";     Url = "http://127.0.0.1:8080/" }
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Navixy Live Map - Recovery" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Root: $root" -ForegroundColor Gray
Write-Host ""

Write-Log "Recovery started (VerifyOnly=$VerifyOnly, RestartServicesOnly=$RestartServicesOnly)"

$failed = @()
foreach ($ep in $endpoints) {
    $ok = Test-Endpoint -Url $ep.Url
    if ($ok) {
        Write-Host "  OK   $($ep.Name)" -ForegroundColor Green
        Write-Log "$($ep.Name) OK"
    } else {
        Write-Host "  FAIL $($ep.Name)" -ForegroundColor Red
        Write-Log "$($ep.Name) FAIL" "ERROR"
        $failed += $ep.Name
    }
}

if ($failed.Count -eq 0) {
    Write-Host ""
    Write-Host "All endpoints OK. No recovery needed." -ForegroundColor Green
    Write-Log "All healthy, exit"
    exit 0
}

if ($VerifyOnly) {
    Write-Host ""
    Write-Host "VerifyOnly: not restarting. Run without -VerifyOnly to recover." -ForegroundColor Yellow
    Write-Log "VerifyOnly, exit without recovery"
    exit 1
}

Write-Host ""
Write-Host "Recovery: attempting restart..." -ForegroundColor Yellow
Write-Log "Starting recovery"

# 1) Restart Windows services if present
$serviceNames = @("NavixyApi", "NavixyQuickTunnel", "NavixyDashboard", "NavixyUrlSync")
$anyService = $false
foreach ($svc in $serviceNames) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        $anyService = $true
        Write-Log "Restarting Windows service: $svc" "WARN"
        try {
            Restart-Service -Name $svc -Force -ErrorAction Stop
            Write-Host "  Restarted service: $svc" -ForegroundColor Green
        } catch {
            Write-Host "  Failed to restart $svc : $_" -ForegroundColor Red
            Write-Log "Restart $svc failed: $_" "ERROR"
        }
    }
}
if ($anyService) {
    Write-Host "Waiting 15s for services to stabilize..." -ForegroundColor Gray
    Start-Sleep -Seconds 15
    $failed = @()
    foreach ($ep in $endpoints) {
        if (-not (Test-Endpoint -Url $ep.Url)) { $failed += $ep.Name }
    }
    if ($failed.Count -eq 0) {
        Write-Host "All endpoints OK after service restart." -ForegroundColor Green
        Write-Log "Recovery succeeded (services)"
        exit 0
    }
}

if ($RestartServicesOnly) {
    Write-Host "RestartServicesOnly: not starting start_all.ps1." -ForegroundColor Yellow
    Write-Log "RestartServicesOnly, exit"
    exit 1
}

# 2) Free ports and run start_all.ps1 (manual stack)
Write-Log "Stopping processes on 8767, 8768, 8080"
Stop-ProcessesOnPorts -Ports @(8767, 8768, 8080)
Start-Sleep -Seconds 3

$venvPython = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Write-Host "ERROR: .venv not found. Cannot run start_all.ps1" -ForegroundColor Red
    Write-Log "venv not found" "ERROR"
    exit 1
}

Write-Host "Starting full stack (start_all.ps1 in new window)..." -ForegroundColor Yellow
Write-Log "Launching start_all.ps1"
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root'; .\start_all.ps1"
Write-Host "Waiting 20s for services to come up..." -ForegroundColor Gray
Start-Sleep -Seconds 20

$failed = @()
foreach ($ep in $endpoints) {
    if (-not (Test-Endpoint -Url $ep.Url)) { $failed += $ep.Name }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "Recovery complete. All endpoints OK." -ForegroundColor Green
    Write-Log "Recovery succeeded (start_all)"
    Start-Process "http://127.0.0.1:8080/index.html"
    exit 0
} else {
    Write-Host "Some endpoints still down: $($failed -join ', '). Check the new start_all window and logs." -ForegroundColor Red
    Write-Log "Recovery incomplete: $($failed -join ', ')" "ERROR"
    exit 1
}
