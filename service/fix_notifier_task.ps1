
# Convert TeltonikaNgrokNotify from NSSM service -> Scheduled Task at user logon
# Scheduled tasks run in the user's session (clipboard + Phone Link work correctly)

$logFile = "D:\New_Recovery\2Plus\navixy-live-map\service\logs\notifier_task_install.txt"
Start-Transcript -Path $logFile -Force
$ErrorActionPreference = "Continue"

$nssm       = "C:\ProgramData\chocolatey\bin\nssm.exe"
$scriptPath = "D:\New_Recovery\2Plus\navixy-live-map\service\ngrok_sms_notifier.ps1"
$taskName   = "TeltonikaNgrokNotify"
$user       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "=== Converting Notifier to Scheduled Task ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date)"
Write-Host "Current user: $user"

# 1. Remove NSSM service
Write-Host ""
Write-Host "1. Removing NSSM service TeltonikaNgrokNotify..."
& $nssm stop   TeltonikaNgrokNotify 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 2
& $nssm remove TeltonikaNgrokNotify confirm 2>&1 | ForEach-Object { Write-Host "  $_" }

# 2. Remove any existing scheduled task with same name
Write-Host ""
Write-Host "2. Removing existing scheduled task (if any)..."
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# 3. Create scheduled task
Write-Host ""
Write-Host "3. Creating scheduled task '$taskName'..."

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId $user `
    -LogonType Interactive `
    -RunLevel Highest

$task = Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Teltonika Ngrok SMS Notifier - watches for ngrok port changes, copies SMS to clipboard" `
    -Force

if ($task) {
    Write-Host "  Scheduled task created OK" -ForegroundColor Green
} else {
    Write-Host "  Failed to create scheduled task" -ForegroundColor Red
}

# 4. Start it now (for current session)
Write-Host ""
Write-Host "4. Starting notifier task NOW..."
Start-ScheduledTask -TaskName $taskName 2>&1 | ForEach-Object { Write-Host "  $_" }
Start-Sleep -Seconds 3

# 5. Verify
Write-Host ""
Write-Host "=== Final Check ===" -ForegroundColor Cyan
$taskInfo = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($taskInfo) {
    $taskStatus = (Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue)
    Write-Host "  Task: $($taskInfo.State)" -ForegroundColor Green
    Write-Host "  Last Run: $($taskStatus.LastRunTime)"
    Write-Host "  Next Run: $($taskStatus.NextRunTime)"
} else {
    Write-Host "  Task not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Services still active:"
foreach ($svcName in @("TeltonikaBroker","TeltonikaNgrok")) {
    $s = Get-Service $svcName -ErrorAction SilentlyContinue
    if ($s) { Write-Host "  $svcName : $($s.Status)" -ForegroundColor $(if ($s.Status -eq "Running") {"Green"} else {"Red"}) }
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
Write-Host "  Notifier will now auto-start on every login in YOUR user session" -ForegroundColor Green
Write-Host "  Clipboard + Phone Link will work correctly" -ForegroundColor Green
Stop-Transcript
