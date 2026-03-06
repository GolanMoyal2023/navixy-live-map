
# Check broker status and watch for new connections
Write-Host "=== Processes on broker ports ===" -ForegroundColor Cyan
$pidList = @()
netstat -ano | Select-String ":15027" | Select-String "LISTENING" | ForEach-Object {
    $parts = ($_ -replace '\s+', ' ').Trim() -split ' '
    $pidStr = $parts[-1]
    if ($pidStr -match '^\d+$') {
        $pidList += $pidStr
        $p = Get-Process -Id $pidStr -ErrorAction SilentlyContinue
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$pidStr" -ErrorAction SilentlyContinue).CommandLine
        Write-Host "  Port 15027 -> PID $pidStr : $($p.Name)"
        Write-Host "  CMD: $cmd"
    }
}

Write-Host ""
Write-Host "=== ESTABLISHED connections on 15027 ===" -ForegroundColor Cyan
$established = netstat -ano | Select-String ":15027" | Select-String "ESTABLISHED|SYN"
if ($established) { $established | ForEach-Object { Write-Host "  $_" } }
else { Write-Host "  None (no devices connected yet)" -ForegroundColor Yellow }

Write-Host ""
Write-Host "=== Latest broker log ===" -ForegroundColor Cyan
$log = "D:\New_Recovery\2Plus\navixy-live-map\service\logs\broker.err.log"
Write-Host "  Current tail:"
Get-Content $log -Tail 5

Write-Host ""
Write-Host "  Watching for 30 seconds..."
$before = (Get-Item $log).Length
Start-Sleep -Seconds 30
$after  = (Get-Item $log).Length

if ($after -gt $before) {
    Write-Host "  ** NEW LOG ACTIVITY DETECTED! **" -ForegroundColor Green
    Get-Content $log -Tail 20
} else {
    Write-Host "  No new log entries in 30 seconds" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Ngrok connection count ===" -ForegroundColor Cyan
try {
    $r = Invoke-RestMethod "http://localhost:4040/api/tunnels" -TimeoutSec 5
    $t = $r.tunnels | Where-Object { $_.proto -eq "tcp" } | Select-Object -First 1
    Write-Host "  Total connections through tunnel: $($t.metrics.conns.count)"
} catch {}
