
$nssm = "C:\ProgramData\chocolatey\bin\nssm.exe"
Write-Host "=== Restarting TeltonikaBroker ===" -ForegroundColor Cyan
& $nssm restart TeltonikaBroker
Start-Sleep -Seconds 6

$status = & $nssm status TeltonikaBroker
Write-Host "Status: $status"

# Verify port 8768 is listening
$listening = netstat -ano | Select-String ":8768" | Select-String "LISTENING"
if ($listening) {
    Write-Host "Port 8768 LISTENING - broker is up!" -ForegroundColor Green
} else {
    Write-Host "Port 8768 not yet listening, waiting 6 more seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 6
    $listening2 = netstat -ano | Select-String ":8768" | Select-String "LISTENING"
    if ($listening2) {
        Write-Host "Port 8768 LISTENING now!" -ForegroundColor Green
    } else {
        Write-Host "Port 8768 still NOT listening - check log" -ForegroundColor Red
        $logDir = "D:\New_Recovery\2Plus\navixy-live-map\service\logs"
        Get-Content "$logDir\broker.err.log" -Tail 25
    }
}

# Test the new RUTX11 endpoint
Write-Host ""
Write-Host "=== Testing /api/rutx11/scanners ===" -ForegroundColor Cyan
try {
    $r = Invoke-RestMethod "http://localhost:8768/api/rutx11/scanners" -TimeoutSec 8
    Write-Host "OK - registered scanners: $($r.scanners | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

# Test /api/rutx11 with a sample payload
Write-Host ""
Write-Host "=== Sending test RUTX11 webhook ===" -ForegroundColor Cyan
$samplePayload = @{
    host = "RUTX11"
    lat  = 32.000
    lng  = 34.000
    data = @(
        @{ mac = "7c:d9:f4:07:f9:5c"; rssi = -65; battery = 80; name = "Eybe2plus1" },
        @{ mac = "7c:d9:f4:00:35:36"; rssi = -70; battery = 75; name = "Eybe2plus2" }
    )
} | ConvertTo-Json -Depth 3

try {
    $rr = Invoke-RestMethod "http://localhost:8768/api/rutx11" -Method POST `
        -Body $samplePayload -ContentType "application/json" -TimeoutSec 8
    Write-Host "OK: $($rr | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}

# Test /data
Write-Host ""
Write-Host "=== Testing /data ===" -ForegroundColor Cyan
try {
    $d = Invoke-RestMethod "http://localhost:8768/data" -TimeoutSec 8
    Write-Host "OK - trackers: $($d.trackers.Count), beacons: $($d.beacons.Count)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Beacons:" -ForegroundColor Yellow
    $d.beacons | ForEach-Object {
        Write-Host "  $($_.name) ($($_.mac)) source=$($_.source) lat=$($_.lat) lng=$($_.lng)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "FAIL: $_" -ForegroundColor Red
}
