# One-step: Fix Cloudflare tunnel permissions and restart service
# Run as user with config (fix copy), then as Admin (restart). Or run elevated and fix copy from current user.
# Usage: .\fix_and_start_cloudflare_tunnel.ps1

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cloudflare Tunnel – Fix & Start" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Copy config to repo .cloudflared (so service can read it)
Write-Host "[1/3] Copying Cloudflare config to repo (service-accessible)..." -ForegroundColor Yellow
& "$PSScriptRoot\fix_tunnel_permissions.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Fix permissions step failed. Ensure config exists in $env:USERPROFILE\.cloudflared\" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Restart service (requires Admin)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[2/3] Restart service: Run as Administrator:" -ForegroundColor Yellow
    Write-Host "      Restart-Service -Name NavixyTunnel -Force" -ForegroundColor White
    Write-Host "      Or run this script in an elevated PowerShell." -ForegroundColor Gray
    exit 0
}

Write-Host "[2/3] Restarting NavixyTunnel service..." -ForegroundColor Yellow
try {
    Stop-Service -Name "NavixyTunnel" -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    Start-Service -Name "NavixyTunnel" -ErrorAction Stop
    Start-Sleep -Seconds 5
    Write-Host "Service restarted." -ForegroundColor Green
} catch {
    Write-Host "Restart failed: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Verify
Write-Host "[3/3] Verifying..." -ForegroundColor Yellow
$service = Get-Service -Name "NavixyTunnel" -ErrorAction SilentlyContinue
$proc = Get-Process cloudflared -ErrorAction SilentlyContinue
$logPath = Join-Path $PSScriptRoot "logs\navixy_tunnel.log"

Write-Host "  Service status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' })
Write-Host "  cloudflared process: $(if ($proc) { "Running (PID $($proc.Id))" } else { "Not running" })" -ForegroundColor $(if ($proc) { 'Green' } else { 'Yellow' })
if (Test-Path $logPath) {
    Write-Host ""
    Write-Host "Last 10 log lines:" -ForegroundColor Gray
    Get-Content $logPath -Tail 10 -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($service.Status -eq 'Running' -and $proc) {
    Write-Host "Tunnel fix complete. Check Cloudflare dashboard for 'Registered tunnel connection'." -ForegroundColor Green
} else {
    Write-Host "Service or cloudflared may still be starting. Check $logPath for errors." -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
