$ErrorActionPreference = "Stop"

. "$PSScriptRoot\\env.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting Cloudflare Named Tunnel" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tunnel ID: e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab" -ForegroundColor Yellow
Write-Host "Hostname: navixy-livemap.moyals.net" -ForegroundColor Yellow
Write-Host "Service: http://127.0.0.1:$env:PORT" -ForegroundColor Yellow
Write-Host ""

# Check if cloudflared is available
$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
    Write-Host "ERROR: cloudflared not found in PATH" -ForegroundColor Red
    Write-Host "Please install cloudflared:" -ForegroundColor Yellow
    Write-Host "  winget install --id Cloudflare.cloudflared -e" -ForegroundColor White
    exit 1
}

# Check if config file exists (try multiple paths - shared location first for service)
# Use try-catch to handle permission errors gracefully
$configPaths = @(
    "$PSScriptRoot\..\.cloudflared\config.yml",  # Shared location (service-accessible)
    "$env:USERPROFILE\.cloudflared\config.yml",
    "C:\Users\$env:USERNAME\.cloudflared\config.yml",
    "C:\Users\GolanMoyal\.cloudflared\config.yml"
)

$configPath = $null
foreach ($path in $configPaths) {
    try {
        if (Test-Path $path -ErrorAction Stop) {
            $configPath = $path
            break
        }
    } catch {
        # Skip paths we can't access (permission denied)
        continue
    }
}

if (-not $configPath) {
    Write-Host "ERROR: Cloudflare config not found in any of these locations:" -ForegroundColor Red
    foreach ($path in $configPaths) {
        Write-Host "  - $path" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Run fix_tunnel_permissions.ps1 to copy config to shared location" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using config: $configPath" -ForegroundColor Cyan

# Change to config directory so relative paths work
$configDir = Split-Path -Parent $configPath
$configFileName = Split-Path -Leaf $configPath
Push-Location $configDir

Write-Host "Starting tunnel from: $configDir" -ForegroundColor Cyan
Write-Host "Config file: $configFileName" -ForegroundColor Cyan

# Verify credentials file exists in this directory
$credsFile = "e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json"
if (-not (Test-Path $credsFile)) {
    Write-Host "ERROR: Credentials file not found: $credsFile" -ForegroundColor Red
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "Files in directory:" -ForegroundColor Yellow
    Get-ChildItem | Select-Object Name | Format-Table
    Pop-Location
    exit 1
}

Write-Host "Credentials file found: $credsFile" -ForegroundColor Green
Write-Host "Starting tunnel..." -ForegroundColor Green
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

try {
    # Run the named tunnel using relative config path
    # Config path is now relative to current directory
    & cloudflared tunnel --config $configFileName run e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab
} finally {
    Pop-Location
}
