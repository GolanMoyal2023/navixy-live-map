
Start-Transcript -Path "D:\New_Recovery\2Plus\navixy-live-map\service\logs\restart2.log" -Force
$nssm = "C:\ProgramData\chocolatey\bin\nssm.exe"
Write-Host "Killing port 8768 process..."
$procs = Get-NetTCPConnection -LocalPort 8768 -State Listen -ErrorAction SilentlyContinue
foreach ($p in $procs) { Stop-Process -Id $p.OwningProcess -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3
Write-Host "Starting TeltonikaBroker..."
& $nssm start TeltonikaBroker
Start-Sleep -Seconds 6
$s = & $nssm status TeltonikaBroker
Write-Host "Status: $s"
Stop-Transcript
