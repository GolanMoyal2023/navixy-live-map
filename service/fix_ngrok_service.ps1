
# Fix TeltonikaNgrok service - use explicit config file so LocalSystem finds authtoken
# Run as Administrator

$logFile = "D:\New_Recovery\2Plus\navixy-live-map\service\logs\ngrok_fix_log.txt"
Start-Transcript -Path $logFile -Force

$nssm      = "C:\ProgramData\chocolatey\bin\nssm.exe"
$ngrok     = "C:\Program Files\WinGet\Links\ngrok.exe"
$cfgFile   = "D:\New_Recovery\2Plus\navixy-live-map\service\ngrok.yml"
$logDir    = "D:\New_Recovery\2Plus\navixy-live-map\service\logs"
$root      = "D:\New_Recovery\2Plus\navixy-live-map"

Write-Host "=== Fixing TeltonikaNgrok service ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date)"

# Stop the paused/failed service
Write-Host "Stopping TeltonikaNgrok..."
& $nssm stop TeltonikaNgrok 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 3

# Clear old error log
$errLog = "$logDir\ngrok.err.log"
if (Test-Path $errLog) { Clear-Content $errLog }

# Update the service Args to include --config flag
$newArgs = "tcp 15027 --config=`"$cfgFile`""
Write-Host "Setting new Args: $newArgs"
& $nssm set TeltonikaNgrok Application $ngrok 2>&1 | ForEach-Object { Write-Host "  $_" }
& $nssm set TeltonikaNgrok AppParameters $newArgs 2>&1 | ForEach-Object { Write-Host "  $_" }
& $nssm set TeltonikaNgrok AppDirectory $root 2>&1 | ForEach-Object { Write-Host "  $_" }

# Restart the service
Write-Host ""
Write-Host "Starting TeltonikaNgrok..."
& $nssm start TeltonikaNgrok 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 8

# Check result
Write-Host ""
Write-Host "=== Status ===" -ForegroundColor Cyan
$s = Get-Service TeltonikaNgrok -ErrorAction SilentlyContinue
if ($s) { Write-Host "  TeltonikaNgrok: $($s.Status)" -ForegroundColor $(if ($s.Status -eq "Running") {"Green"} else {"Red"}) }

Write-Host ""
Write-Host "=== Ngrok error log ===" -ForegroundColor Cyan
if ((Get-Item $errLog -ErrorAction SilentlyContinue).Length -gt 0) {
    Get-Content $errLog -Tail 20
} else {
    Write-Host "  (empty - good!)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Ngrok API check ===" -ForegroundColor Cyan
Start-Sleep -Seconds 3
try {
    $r = Invoke-RestMethod "http://localhost:4040/api/tunnels" -TimeoutSec 5
    $t = $r.tunnels | Where-Object { $_.proto -eq "tcp" } | Select-Object -First 1
    if ($t) { Write-Host "  TUNNEL ACTIVE: $($t.public_url)" -ForegroundColor Green }
    else     { Write-Host "  No TCP tunnel found" -ForegroundColor Yellow }
} catch {
    Write-Host "  Ngrok API not reachable: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
Stop-Transcript
