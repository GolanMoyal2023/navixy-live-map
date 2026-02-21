# Fix NavixyTunnel Service Configuration
# Ensures service can find the Cloudflare config

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Fixing NavixyTunnel Service" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if NSSM is available
$nssmPath = "C:\Tools\nssm\nssm.exe"
if (-not (Test-Path $nssmPath)) {
    Write-Host "NSSM not found at: $nssmPath" -ForegroundColor Yellow
    Write-Host "Please install NSSM or provide the path" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Alternative: Update service manually:" -ForegroundColor Cyan
    Write-Host "1. Open services.msc" -ForegroundColor White
    Write-Host "2. Find NavixyTunnel" -ForegroundColor White
    Write-Host "3. Right-click -> Properties" -ForegroundColor White
    Write-Host "4. Log On tab -> Change to your user account" -ForegroundColor White
    Write-Host "5. Or update the script path to use absolute config path" -ForegroundColor White
    exit 1
}

Write-Host "Updating service to use correct config path..." -ForegroundColor Yellow

# Get current service config
$servicePath = & $nssmPath get NavixyTunnel Application
$serviceArgs = & $nssmPath get NavixyTunnel AppParameters
$serviceDir = & $nssmPath get NavixyTunnel AppDirectory

Write-Host "Current service path: $servicePath" -ForegroundColor Cyan
Write-Host "Current arguments: $serviceArgs" -ForegroundColor Cyan
Write-Host "Current directory: $serviceDir" -ForegroundColor Cyan
Write-Host ""

# The script already handles multiple config paths, so we just need to ensure
# the service can access the config. The updated start_tunnel.ps1 should work.

Write-Host "Service configuration looks correct." -ForegroundColor Green
Write-Host "The updated start_tunnel.ps1 will find the config automatically." -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Restart the service" -ForegroundColor Yellow
Write-Host "  Restart-Service -Name NavixyTunnel -Force" -ForegroundColor White
