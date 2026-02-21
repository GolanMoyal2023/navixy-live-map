# Restart NavixyTunnel Service
# Requires Administrator privileges

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Restarting NavixyTunnel Service" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run PowerShell as Administrator and try again" -ForegroundColor Yellow
    Write-Host "Or run manually:" -ForegroundColor Yellow
    Write-Host "  Restart-Service -Name NavixyTunnel -Force" -ForegroundColor White
    exit 1
}

# Stop service
Write-Host "Stopping NavixyTunnel service..." -ForegroundColor Yellow
try {
    Stop-Service -Name "NavixyTunnel" -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    Write-Host "Service stopped" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not stop service: $_" -ForegroundColor Yellow
}

# Start service
Write-Host "Starting NavixyTunnel service..." -ForegroundColor Yellow
try {
    Start-Service -Name "NavixyTunnel" -ErrorAction Stop
    Start-Sleep -Seconds 5
    Write-Host "Service started" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not start service: $_" -ForegroundColor Red
    exit 1
}

# Check status
Write-Host ""
Write-Host "Checking service status..." -ForegroundColor Yellow
$service = Get-Service -Name "NavixyTunnel"
Write-Host "Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Red' })

# Wait a bit and check logs
Start-Sleep -Seconds 5
Write-Host ""
Write-Host "Recent tunnel logs:" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
Get-Content (Join-Path $PSScriptRoot "logs\navixy_tunnel.log") -Tail 20 -ErrorAction SilentlyContinue
Write-Host "----------------------------------------" -ForegroundColor Gray

# Check if cloudflared process is running
Write-Host ""
Write-Host "Checking cloudflared process..." -ForegroundColor Yellow
$proc = Get-Process cloudflared -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "✅ Cloudflared process running (PID: $($proc.Id))" -ForegroundColor Green
} else {
    Write-Host "⚠️  Cloudflared process not running - check logs for errors" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($service.Status -eq 'Running' -and $proc) {
    Write-Host "✅ Service restarted successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "Tunnel should be connecting to Cloudflare..." -ForegroundColor Green
    Write-Host "Check Cloudflare dashboard to verify connection" -ForegroundColor Yellow
} elseif ($service.Status -eq 'Running') {
    Write-Host "⚠️  Service running but cloudflared not started" -ForegroundColor Yellow
    Write-Host "Check logs above for errors" -ForegroundColor Yellow
} else {
    Write-Host "⚠️  Service status: $($service.Status)" -ForegroundColor Yellow
    Write-Host "Check logs for errors" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
