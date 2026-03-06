
Write-Host "=== Port 8765 (Navixy API) ===" -ForegroundColor Cyan
$listening = netstat -ano | Select-String ":8765" | Select-String "LISTENING"
if ($listening) {
    $parts = ($listening -replace '\s+', ' ').Trim() -split ' '
    $pid8765 = $parts[-1]
    $p = Get-Process -Id $pid8765 -ErrorAction SilentlyContinue
    Write-Host "  Listening - PID $pid8765 : $($p.Name)" -ForegroundColor Green
} else {
    Write-Host "  Port 8765 NOT LISTENING - Navixy server.py is DOWN!" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Navixy API log (last 20 lines) ===" -ForegroundColor Cyan
$navLog = "D:\New_Recovery\2Plus\navixy-live-map\service\logs\navixy_api.err.log"
if (Test-Path $navLog) { Get-Content $navLog -Tail 20 }

Write-Host ""
Write-Host "=== All Python processes ===" -ForegroundColor Cyan
Get-Process python -ErrorAction SilentlyContinue | Format-Table Id, CPU, WS -AutoSize

Write-Host ""
Write-Host "=== All listening ports (relevant) ===" -ForegroundColor Cyan
netstat -ano | Select-String "LISTENING" | Select-String "8765|8768|15027|4040"
