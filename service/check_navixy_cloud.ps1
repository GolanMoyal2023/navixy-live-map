
# Try to reach Navixy cloud directly and check SKODA's last update
$hash = "f038d4c96bfc683cdc52337824f7e5f0"

Write-Host "=== Direct Navixy Cloud API check ===" -ForegroundColor Cyan

# First try /tracker/list to see all trackers
try {
    $r = Invoke-RestMethod "https://api.navixy.com/v2/tracker/list?hash=$hash" -TimeoutSec 10
    if ($r.success) {
        Write-Host "  Cloud API: OK" -ForegroundColor Green
        $r.list | ForEach-Object {
            Write-Host "  Tracker: $($_.label) [id=$($_.id)] source=$($_.source.device_id)"
        }
    } else {
        Write-Host "  Cloud API error: $($r.status.description)" -ForegroundColor Red
    }
} catch {
    Write-Host "  Cloud API unreachable: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Check SKODA last GPS state ===" -ForegroundColor Cyan
# SKODA IMEI = 864275078490847
# Try to get tracker state for SKODA
try {
    # First get the tracker ID
    $listR = Invoke-RestMethod "https://api.navixy.com/v2/tracker/list?hash=$hash" -TimeoutSec 10
    $skoda = $listR.list | Where-Object { $_.source.device_id -eq "864275078490847" }
    if ($skoda) {
        Write-Host "  SKODA tracker ID: $($skoda.id)" -ForegroundColor Green
        # Get last state
        $state = Invoke-RestMethod "https://api.navixy.com/v2/tracker/get_state?hash=$hash&tracker_id=$($skoda.id)" -TimeoutSec 10
        Write-Host "  Last GPS update : $($state.state.gps.updated)" -ForegroundColor Yellow
        Write-Host "  Last connection : $($state.state.connection_status)"
        Write-Host "  Position        : $($state.state.gps.location.lat), $($state.state.gps.location.lng)"
    } else {
        Write-Host "  SKODA not found in tracker list" -ForegroundColor Red
    }
} catch {
    Write-Host "  State check error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== server.py process alive ===" -ForegroundColor Cyan
$p = Get-Process -Id 14708 -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "  PID 14708 running: $($p.Name), CPU=$($p.CPU), Handles=$($p.Handles)" -ForegroundColor Green
} else {
    Write-Host "  PID 14708 NOT FOUND" -ForegroundColor Red
}
