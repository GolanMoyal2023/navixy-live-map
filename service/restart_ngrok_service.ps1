
# Restart TeltonikaNgrok properly (stop dependents first, then restart chain)
$logFile = "D:\New_Recovery\2Plus\navixy-live-map\service\logs\ngrok_restart_log.txt"
Start-Transcript -Path $logFile -Force
$ErrorActionPreference = "Continue"

$nssm    = "C:\ProgramData\chocolatey\bin\nssm.exe"
$logDir  = "D:\New_Recovery\2Plus\navixy-live-map\service\logs"

Write-Host "=== Restart Ngrok Service Chain ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date)"

# 1. Stop dependent service first
Write-Host "1. Stopping TeltonikaNgrokNotify..."
& $nssm stop TeltonikaNgrokNotify 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 3

# 2. Force kill any remaining ngrok.exe process
Write-Host "2. Force killing any ngrok.exe process..."
Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 3. Stop TeltonikaNgrok
Write-Host "3. Stopping TeltonikaNgrok..."
& $nssm stop TeltonikaNgrok 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 3

# 4. Clear error log
$errLog = "$logDir\ngrok.err.log"
if (Test-Path $errLog) { Clear-Content $errLog }

# 5. Start TeltonikaNgrok
Write-Host "4. Starting TeltonikaNgrok..."
& $nssm start TeltonikaNgrok 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 10

# 6. Check ngrok status
$s = Get-Service TeltonikaNgrok -ErrorAction SilentlyContinue
Write-Host "   Status: $($s.Status)" -ForegroundColor $(if ($s.Status -eq "Running") {"Green"} else {"Red"})

# 7. Check error log
Write-Host ""
Write-Host "Ngrok error log:"
if ((Get-Item $errLog -ErrorAction SilentlyContinue).Length -gt 0) {
    Get-Content $errLog -Tail 10
} else {
    Write-Host "  (empty)" -ForegroundColor Green
}

# 8. Check API
Write-Host ""
Write-Host "Checking ngrok API..."
Start-Sleep -Seconds 3
try {
    $r = Invoke-RestMethod "http://localhost:4040/api/tunnels" -TimeoutSec 5
    $t = $r.tunnels | Where-Object { $_.proto -eq "tcp" } | Select-Object -First 1
    if ($t) { Write-Host "  TUNNEL ACTIVE: $($t.public_url)" -ForegroundColor Green }
    else     { Write-Host "  No TCP tunnel" -ForegroundColor Yellow }
} catch {
    Write-Host "  API not reachable: $_" -ForegroundColor Red
}

# 9. Start notifier
Write-Host ""
Write-Host "5. Starting TeltonikaNgrokNotify..."
& $nssm start TeltonikaNgrokNotify 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 3

# 10. Final status
Write-Host ""
Write-Host "=== Final Status ===" -ForegroundColor Cyan
foreach ($svcName in @("TeltonikaBroker","TeltonikaNgrok","TeltonikaNgrokNotify")) {
    $s = Get-Service $svcName -ErrorAction SilentlyContinue
    if ($s) { Write-Host "  $svcName : $($s.Status)" -ForegroundColor $(if ($s.Status -eq "Running") {"Green"} elseif ($s.Status -eq "Paused") {"Yellow"} else {"Red"}) }
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
Stop-Transcript
