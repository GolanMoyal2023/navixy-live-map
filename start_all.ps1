<#
.SYNOPSIS
    Start all services for the Navixy Live Map

.DESCRIPTION
    Launches two background windows:
      1. Navixy Server  (port 8767) - Motorized GSE positions from Navixy cloud API
      2. Teltonika Broker (port 8768) - BLE beacons from RUTX11 webhook + FMC direct TCP

    The map's "Both" button fetches from both ports simultaneously and combines them.
#>

$Root   = "D:\New_Recovery\2Plus\navixy-live-map"
$Python = "$Root\.venv\Scripts\python.exe"

if (-not (Test-Path $Python)) {
    Write-Host "ERROR: Python venv not found at $Python" -ForegroundColor Red
    Write-Host "       Run: python -m venv .venv && .venv\Scripts\pip install -r requirements.txt" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Navixy Live Map - Starting all services"   -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------
# 1.  Navixy Server on port 8767
#     Proxies Navixy cloud API -> returns tracker rows for motorized GSE
# ------------------------------------------------------------------
Write-Host "[1/2] Navixy Server (port 8767) - Motorized GSE..." -ForegroundColor Yellow

$navixyCmd = "set PORT=8767&& set NAVIXY_API_HASH=f038d4c96bfc683cdc52337824f7e5f0&& title Navixy-Server && `"$Python`" `"$Root\server.py`""
Start-Process "cmd.exe" -ArgumentList "/k", $navixyCmd -WorkingDirectory $Root -WindowStyle Normal
Start-Sleep -Seconds 2

# ------------------------------------------------------------------
# 2.  Teltonika Broker on port 8768
#     Receives CODEC8 TCP (FMC003/FMC650) + RUTX11 webhooks
#     Returns BLE beacon positions from SQL
# ------------------------------------------------------------------
Write-Host "[2/2] Teltonika Broker (port 8768) - BLE beacons + direct FMC..." -ForegroundColor Yellow

$brokerCmd = "title Teltonika-Broker && `"$Python`" `"$Root\teltonika_broker.py`""
Start-Process "cmd.exe" -ArgumentList "/k", $brokerCmd -WorkingDirectory $Root -WindowStyle Normal
Start-Sleep -Seconds 4

# ------------------------------------------------------------------
# Health check
# ------------------------------------------------------------------
Write-Host ""
Write-Host "Checking services (waiting a few seconds)..." -ForegroundColor Gray
Start-Sleep -Seconds 3

foreach ($check in @(
    @{ Port=8767; Name="Navixy Server  " },
    @{ Port=8768; Name="Broker         " }
)) {
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:$($check.Port)/health" -TimeoutSec 4 -UseBasicParsing -ErrorAction Stop
        Write-Host "  $($check.Name) :  OK  (port $($check.Port))" -ForegroundColor Green
    } catch {
        Write-Host "  $($check.Name) :  starting... (port $($check.Port))" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Map:  https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
Write-Host "  Tip:  Select [Both] in the top-left to see"              -ForegroundColor Gray
Write-Host "        motorized GSE + BLE beacons on one map"            -ForegroundColor Gray
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
