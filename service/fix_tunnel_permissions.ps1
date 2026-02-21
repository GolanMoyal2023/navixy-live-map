# Fix Tunnel Service Permissions
# Copies Cloudflare config from user profile to repo .cloudflared so NavixyTunnel service can read it.
# Run once as the user who has the config (e.g. GolanMoyal), then restart NavixyTunnel.

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Fixing Tunnel Service Permissions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Source paths (current user profile - where cloudflared login wrote the files)
$sourceConfig = "$env:USERPROFILE\.cloudflared\config.yml"
$sourceCreds = "$env:USERPROFILE\.cloudflared\e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json"
# Fallback explicit path if needed
if (-not (Test-Path $sourceConfig)) {
    $sourceConfig = "C:\Users\GolanMoyal\.cloudflared\config.yml"
    $sourceCreds = "C:\Users\GolanMoyal\.cloudflared\e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json"
}

# Destination: repo .cloudflared (start_tunnel.ps1 looks here first - service can read it when AppDirectory = repo root)
$repoRoot = Split-Path $PSScriptRoot -Parent
$sharedCloudflared = Join-Path $repoRoot ".cloudflared"
$destConfig = Join-Path $sharedCloudflared "config.yml"
$destCreds = Join-Path $sharedCloudflared "e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json"
Write-Host "Repo root: $repoRoot" -ForegroundColor Gray
Write-Host "Destination .cloudflared: $sharedCloudflared" -ForegroundColor Gray

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

# Update config file: make credentials path relative (so it works in repo .cloudflared)
Write-Host "Updating config file paths..." -ForegroundColor Yellow
$configContent = Get-Content -Path $destConfig -Raw
$configContent = $configContent -replace 'credentials-file:\s*[^\r\n]+', 'credentials-file: e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json'
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
Write-Host "start_tunnel.ps1 already uses this location first." -ForegroundColor Green
Write-Host "Restart the service: Restart-Service -Name NavixyTunnel -Force" -ForegroundColor Yellow
