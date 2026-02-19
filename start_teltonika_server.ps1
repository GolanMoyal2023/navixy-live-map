# Start Teltonika Direct TCP Server
# ===================================
# This server receives data directly from Teltonika FMC devices,
# bypassing Navixy to get ALL beacon data.

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "TELTONIKA DIRECT TCP SERVER" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Activate virtual environment if it exists
if (Test-Path ".venv\Scripts\Activate.ps1") {
    . .\.venv\Scripts\Activate.ps1
}

# Set environment variables
$env:TELTONIKA_TCP_PORT = "5027"
$env:TELTONIKA_API_PORT = "8768"

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  TCP Port: $env:TELTONIKA_TCP_PORT (for Teltonika devices)"
Write-Host "  API Port: $env:TELTONIKA_API_PORT (for data access)"
Write-Host ""
Write-Host "Configure your Teltonika FMC device:" -ForegroundColor Green
Write-Host "  1. Open Teltonika Configurator"
Write-Host "  2. Go to GPRS -> Server Settings"
Write-Host "  3. Add a secondary server:"
Write-Host "     Domain: YOUR_PUBLIC_IP or Dynamic DNS"
Write-Host "     Port: 5027"
Write-Host "     Protocol: TCP"
Write-Host "  4. Save to device"
Write-Host ""
Write-Host "For local testing, use your LAN IP:" -ForegroundColor Cyan

# Get local IP
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } | Select-Object -First 1).IPAddress
Write-Host "  Server: $localIP"
Write-Host "  Port: 5027"
Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Starting server..." -ForegroundColor Green
Write-Host ""

# Run the server
python teltonika_server.py
