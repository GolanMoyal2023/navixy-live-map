# Install Post-Startup Task
# Creates a Windows Task Scheduler task that runs after logon
# to sync tunnel URL and open dashboard

$ErrorActionPreference = "Stop"

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "Installing Post-Startup Task" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

# Check for admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ Please run as Administrator!" -ForegroundColor Red
    exit 1
}

$taskName = "NavixyPostStartupSync"
$scriptPath = "D:\New_Recovery\2Plus\navixy-live-map\service\post_startup_sync.ps1"

# Remove existing task if exists
Write-Host "Checking for existing task..." -ForegroundColor Yellow
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "  Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create the task
Write-Host "Creating scheduled task..." -ForegroundColor Yellow

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Trigger: At logon with a 60 second delay (to let services start)
$trigger = New-ScheduledTaskTrigger -AtLogon
$trigger.Delay = "PT60S"  # 60 second delay

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Syncs Navixy tunnel URL to GitHub and opens dashboard after system startup"

Write-Host ""
Write-Host "✅ Task installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Task: $taskName" -ForegroundColor Cyan
Write-Host "Runs: At user logon (60 second delay)" -ForegroundColor White
Write-Host "Action: Syncs tunnel URL to GitHub, opens dashboard" -ForegroundColor White
Write-Host ""

# Also run it now for immediate effect
Write-Host "Running sync now..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "========================================"  -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================"  -ForegroundColor Green
Write-Host ""
Write-Host "After restart:" -ForegroundColor Yellow
Write-Host "  1. Services start automatically (NavixyApi, NavixyQuickTunnel, NavixyDashboard)" -ForegroundColor White
Write-Host "  2. After you log in, wait 60 seconds" -ForegroundColor White
Write-Host "  3. Post-startup task syncs URL to GitHub" -ForegroundColor White
Write-Host "  4. Dashboard opens in browser" -ForegroundColor White
Write-Host ""
