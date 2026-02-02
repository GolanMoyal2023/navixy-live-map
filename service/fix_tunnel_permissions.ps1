# Fix Tunnel Service Permissions
# Copies Cloudflare config to shared location accessible by service

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Fixing Tunnel Service Permissions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Source paths (GolanMoyal user)
$sourceConfig = "C:\Users\GolanMoyal\.cloudflared\config.yml"
$sourceCreds = "C:\Users\GolanMoyal\.cloudflared\e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json"

# Destination paths (shared location)
$sharedCloudflared = "D:\New_Recovery\2Plus\navixy-live-map\.cloudflared"
$destConfig = Join-Path $sharedCloudflared "config.yml"
$destCreds = Join-Path $sharedCloudflared "e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json"

# Check if source files exist
if (-not (Test-Path $sourceConfig)) {
    Write-Host "ERROR: Source config not found: $sourceConfig" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $sourceCreds)) {
    Write-Host "ERROR: Source credentials not found: $sourceCreds" -ForegroundColor Red
    exit 1
}

# Create destination directory
if (-not (Test-Path $sharedCloudflared)) {
    New-Item -ItemType Directory -Path $sharedCloudflared -Force | Out-Null
    Write-Host "Created directory: $sharedCloudflared" -ForegroundColor Green
}

# Copy config file
Write-Host "Copying config file..." -ForegroundColor Yellow
Copy-Item -Path $sourceConfig -Destination $destConfig -Force
Write-Host "Copied: $destConfig" -ForegroundColor Green

# Copy credentials file
Write-Host "Copying credentials file..." -ForegroundColor Yellow
Copy-Item -Path $sourceCreds -Destination $destCreds -Force
Write-Host "Copied: $destCreds" -ForegroundColor Green

# Update config file to use relative paths for credentials
Write-Host "Updating config file paths..." -ForegroundColor Yellow
$configContent = Get-Content -Path $destConfig -Raw
$configContent = $configContent -replace 'credentials-file: C:\\Users\\GolanMoyal\\.cloudflared\\', 'credentials-file: '
Set-Content -Path $destConfig -Value $configContent -NoNewline
Write-Host "Updated config paths" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Fix Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Config copied to: $destConfig" -ForegroundColor Cyan
Write-Host "Credentials copied to: $destCreds" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next step: Update start_tunnel.ps1 to use this config location" -ForegroundColor Yellow
Write-Host "Then restart the service: Restart-Service -Name NavixyTunnel" -ForegroundColor Yellow
