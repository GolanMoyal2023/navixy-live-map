
Write-Host "=== Port 15027 - TCP vs UDP ===" -ForegroundColor Cyan
netstat -ano | Select-String "15027"

Write-Host ""
Write-Host "=== SKODA latest Navixy state ===" -ForegroundColor Cyan
try {
    $state = Invoke-RestMethod "https://api.navixy.com/v2/tracker/get_state?hash=f038d4c96bfc683cdc52337824f7e5f0&tracker_id=3475504" -TimeoutSec 8
    Write-Host "  Last GPS update : $($state.state.gps.updated)" -ForegroundColor Yellow
    Write-Host "  Connection      : $($state.state.connection_status)"
    Write-Host "  Speed           : $($state.state.gps.speed) km/h"
    Write-Host "  Position        : $($state.state.gps.location.lat), $($state.state.gps.location.lng)"
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Broker incoming connections check ===" -ForegroundColor Cyan
netstat -ano | Select-String ":15027" | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== Current time: $(Get-Date -Format 'HH:mm:ss') ===" -ForegroundColor Gray
