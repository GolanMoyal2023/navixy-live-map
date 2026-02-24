
Write-Host "=== Time: $(Get-Date -Format 'HH:mm:ss') ===" -ForegroundColor Cyan

# Navixy API
Write-Host ""
Write-Host "--- Navixy API ---" -ForegroundColor Cyan
try {
    $r = Invoke-RestMethod "http://localhost:8765/data" -TimeoutSec 8
    foreach ($t in $r.trackers) {
        $marker = if ($t.source.device_id -eq "864275078490847") { " <<< SKODA" } else { "" }
        Write-Host "  $($t.label)$marker  last: $($t.location.updated)" -ForegroundColor $(if ($marker) {"Yellow"} else {"Gray"})
    }
} catch {
    Write-Host "  Navixy API timeout/error: $_" -ForegroundColor Red
}

# Broker trackers
Write-Host ""
Write-Host "--- Broker Trackers ---" -ForegroundColor Cyan
try {
    $b = Invoke-RestMethod "http://localhost:8768/api/trackers" -TimeoutSec 5
    $b | ConvertTo-Json -Depth 3 | Write-Host
} catch {
    Write-Host "  Broker tracker error: $_" -ForegroundColor Red
}

# Ngrok connections
Write-Host ""
Write-Host "--- Ngrok tunnel connections ---" -ForegroundColor Cyan
try {
    $r2 = Invoke-RestMethod "http://localhost:4040/api/tunnels" -TimeoutSec 3
    $t2 = $r2.tunnels | Where-Object { $_.proto -eq "tcp" } | Select-Object -First 1
    Write-Host "  URL: $($t2.public_url)"
    Write-Host "  Total connections: $($t2.metrics.conns.count)"
    Write-Host "  Active now (gauge): $($t2.metrics.conns.gauge)"
} catch {}

# Port 15027 connections
Write-Host ""
Write-Host "--- TCP connections on 15027 ---" -ForegroundColor Cyan
$conns = netstat -ano | Select-String ":15027"
$conns | ForEach-Object { Write-Host "  $_" }

# Latest broker log
Write-Host ""
Write-Host "--- Broker log (last 8 lines) ---" -ForegroundColor Cyan
Get-Content "D:\New_Recovery\2Plus\navixy-live-map\service\logs\broker.err.log" -Tail 8
