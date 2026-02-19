# Run Navixy Live Map locally: send test data + start map server
# Prerequisite: Start the broker first in another terminal:
#   .\.venv\Scripts\python.exe teltonika_broker.py
# Usage: .\run_local.ps1

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Navixy Live Map - Local Run" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check broker is up
try {
    $null = Invoke-RestMethod -Uri "http://127.0.0.1:8768/" -TimeoutSec 2
} catch {
    Write-Host "ERROR: Broker not running. Start it first in another terminal:" -ForegroundColor Red
    Write-Host "  .\.venv\Scripts\python.exe teltonika_broker.py" -ForegroundColor White
    exit 1
}

# Send one test AVL packet so map has real-looking data
Write-Host ""
Write-Host "[1/2] Sending test tracker + BLE packet..." -ForegroundColor Yellow
& .\.venv\Scripts\python.exe send_test_avl.py
Start-Sleep -Seconds 1

# Start HTTP server for map UI (port 8080) - runs in foreground
Write-Host "[2/2] Starting map server on port 8080 (Ctrl+C to stop)..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Map URL:  http://127.0.0.1:8080/index.html" -ForegroundColor White
Write-Host "  Data:     Use 'Direct' (default)." -ForegroundColor White
Write-Host ""
Start-Process "http://127.0.0.1:8080/index.html"
python -m http.server 8080
