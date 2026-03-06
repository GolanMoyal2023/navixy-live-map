
# Check Navixy API for latest tracker/BLE data
try {
    $r = Invoke-RestMethod "http://localhost:8765/data" -TimeoutSec 5
    Write-Host "=== Navixy Trackers ===" -ForegroundColor Cyan
    foreach ($t in $r.trackers) {
        Write-Host "  $($t.label) [IMEI:$($t.source.device_id)]  last: $($t.location.updated)"
    }
} catch {
    Write-Host "Navixy API error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Broker BLE (current) ===" -ForegroundColor Cyan
try {
    $ble = Invoke-RestMethod "http://localhost:8768/api/ble" -TimeoutSec 5
    foreach ($a in $ble.ble_assets) {
        Write-Host "  $($a.name) [$($a.mac)]  paired=$($a.is_paired)  last: $($a.last_update)  tracker: $($a.tracker_imei)"
    }
} catch {
    Write-Host "Broker BLE error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Current time: $(Get-Date) ===" -ForegroundColor Gray
