# Start all Navixy Live Map services (Navixy API, Teltonika broker, Map UI)
# Use this script to run the full stack and record what is needed for maintenance.
# Requires: Python 3, venv with flask requests pyodbc; optional: SQL Server for DB.
# Usage: .\start_all.ps1

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$venvPython = Join-Path $root ".venv\Scripts\python.exe"

if (-not (Test-Path $venvPython)) {
    Write-Host "ERROR: venv not found. Run: python -m venv .venv; .\.venv\Scripts\pip install flask requests pyodbc" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Navixy Live Map - Start All Services" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1) Navixy API server (port 8767) - for map "Navixy" data source
Write-Host "[1/4] Starting Navixy API server (port 8767)..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root'; `$env:PORT='8767'; & '$venvPython' server.py"
Start-Sleep -Seconds 2

# 2) Teltonika broker (TCP 15027, HTTP 8768) - for map "Direct" data + BLE
Write-Host "[2/4] Starting Teltonika broker (TCP 15027, HTTP 8768)..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root'; & '$venvPython' teltonika_broker.py"
Start-Sleep -Seconds 4

# 3) Optional: inject test tracker (no BLE pin - beacon position set by real data or manual POST)
Write-Host "[3/4] Sending test data (optional)..." -ForegroundColor Yellow
try {
    & $venvPython (Join-Path $root "send_test_avl.py") 2>$null
    # To pin Eybe2plus1 to a specific location, run:
    #   Invoke-RestMethod -Uri "http://127.0.0.1:8768/ble/set-position" -Method POST -ContentType "application/json" -Body '{"mac":"7cd9f407f95c","lat":YOUR_LAT,"lng":YOUR_LNG}'
} catch { Write-Host "  (test data skipped - broker may still be starting)" -ForegroundColor Gray }
Start-Sleep -Seconds 1

# 4) Map UI server (port 8080) - foreground in this window
Write-Host "[4/4] Starting map server on port 8080..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Map URL:    http://127.0.0.1:8080/index.html" -ForegroundColor White
Write-Host "  Navixy:     http://127.0.0.1:8767/data  (5032, 6074, SKODA, etc.)" -ForegroundColor White
Write-Host "  Direct:     http://127.0.0.1:8768/data  (broker + BLE)" -ForegroundColor White
Write-Host "  Close this window to stop the map server. Other two windows = Navixy + Broker." -ForegroundColor Gray
Write-Host ""
Start-Process "http://127.0.0.1:8080/index.html"
& (Get-Command python).Source -m http.server 8080
