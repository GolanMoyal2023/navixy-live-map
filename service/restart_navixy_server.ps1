
# Restart the Navixy API server (server.py) - it's been stuck since 15:37
$root   = "D:\New_Recovery\2Plus\navixy-live-map"
$python = "D:\New_Recovery\2Plus\navixy-live-map\.venv\Scripts\python.exe"
$logDir = "D:\New_Recovery\2Plus\navixy-live-map\service\logs"

Write-Host "=== Restarting Navixy API server (server.py) ===" -ForegroundColor Cyan

# Kill existing server.py on port 8765
$oldPid = (netstat -ano | Select-String ":8765" | Select-String "LISTENING" | ForEach-Object {
    ($_ -replace '\s+', ' ').Trim() -split ' ' | Select-Object -Last 1
} | Select-Object -First 1)

if ($oldPid -and $oldPid -match '^\d+$') {
    Write-Host "  Stopping old server.py PID $oldPid..."
    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "  Stopped." -ForegroundColor Green
} else {
    Write-Host "  No existing server on port 8765"
}

# Start fresh
Write-Host "  Starting server.py..."
$proc = Start-Process `
    -FilePath $python `
    -ArgumentList "$root\server.py" `
    -WorkingDirectory $root `
    -RedirectStandardOutput "$logDir\navixy_api.log" `
    -RedirectStandardError  "$logDir\navixy_api.err.log" `
    -NoNewWindow `
    -PassThru

Start-Sleep -Seconds 4

# Verify
$listening = netstat -ano | Select-String ":8765" | Select-String "LISTENING"
if ($listening) {
    Write-Host "  server.py running - port 8765 is LISTENING" -ForegroundColor Green
    Write-Host "  New PID: $($proc.Id)"
} else {
    Write-Host "  server.py may have failed - checking log..." -ForegroundColor Red
    Get-Content "$logDir\navixy_api.err.log" -Tail 10
}

# Quick test
Write-Host ""
Write-Host "  Testing /data endpoint..."
Start-Sleep -Seconds 2
try {
    $r = Invoke-RestMethod "http://localhost:8765/data" -TimeoutSec 8
    Write-Host "  /data OK - got $($r.trackers.Count) trackers" -ForegroundColor Green
    $r.trackers | ForEach-Object {
        Write-Host "    $($_.label) last: $($_.location.updated)"
    }
} catch {
    Write-Host "  /data still not responding: $_" -ForegroundColor Yellow
    Write-Host "  (May need a few more seconds to fetch from Navixy cloud)"
}
