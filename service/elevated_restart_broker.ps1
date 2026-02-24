
# This script runs elevated to restart TeltonikaBroker
Start-Transcript -Path "D:\New_Recovery\2Plus\navixy-live-map\service\logs\restart_broker_elevated.log" -Force

$nssm = "C:\ProgramData\chocolatey\bin\nssm.exe"
Write-Host "=== Elevated restart of TeltonikaBroker ===" -ForegroundColor Cyan

# Stop
Write-Host "Stopping TeltonikaBroker..."
& $nssm stop TeltonikaBroker confirm
Start-Sleep -Seconds 3

# Force-kill any leftover python on port 8768
$procs = Get-NetTCPConnection -LocalPort 8768 -State Listen -ErrorAction SilentlyContinue
foreach ($p in $procs) {
    Write-Host "  Killing PID $($p.OwningProcess) on port 8768..."
    Stop-Process -Id $p.OwningProcess -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# Start
Write-Host "Starting TeltonikaBroker..."
& $nssm start TeltonikaBroker
Start-Sleep -Seconds 7

$status = & $nssm status TeltonikaBroker
Write-Host "Status: $status"

Stop-Transcript
