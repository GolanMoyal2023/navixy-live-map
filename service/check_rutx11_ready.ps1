
Start-Sleep -Seconds 3

# Check elevated restart log
$logFile = "D:\New_Recovery\2Plus\navixy-live-map\service\logs\restart_broker_elevated.log"
if (Test-Path $logFile) {
    Write-Host "=== Elevated restart log ===" -ForegroundColor Cyan
    Get-Content $logFile
} else {
    Write-Host "Log not found - may still be starting" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Port 8768 check ===" -ForegroundColor Cyan
$listening = netstat -ano | Select-String ":8768" | Select-String "LISTENING"
if ($listening) {
    Write-Host "Port 8768 LISTENING" -ForegroundColor Green
    Write-Host $listening
} else {
    Write-Host "Port 8768 NOT listening" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing /api/rutx11/scanners ===" -ForegroundColor Cyan
try {
    $r = Invoke-RestMethod "http://localhost:8768/api/rutx11/scanners" -TimeoutSec 8
    Write-Host "SUCCESS - new RUTX11 endpoint is live!" -ForegroundColor Green
    Write-Host ($r | ConvertTo-Json)
} catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Sending test RUTX11 webhook (2 beacons) ===" -ForegroundColor Cyan
$payload = @{
    host = "RUTX11"
    lat  = 32.0005
    lng  = 34.0005
    data = @(
        @{ mac = "7c:d9:f4:07:f9:5c"; rssi = -65; battery = 80; name = "Eybe2plus1" },
        @{ mac = "7c:d9:f4:00:35:36"; rssi = -70; battery = 75; name = "Eybe2plus2" }
    )
} | ConvertTo-Json -Depth 3

try {
    $resp = Invoke-RestMethod "http://localhost:8768/api/rutx11" -Method POST `
        -Body $payload -ContentType "application/json" -TimeoutSec 8
    Write-Host "SUCCESS:" -ForegroundColor Green
    Write-Host ($resp | ConvertTo-Json -Depth 3)
} catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Broker error log (last 15 lines) ===" -ForegroundColor Cyan
Get-Content "D:\New_Recovery\2Plus\navixy-live-map\service\logs\broker.err.log" -Tail 15
