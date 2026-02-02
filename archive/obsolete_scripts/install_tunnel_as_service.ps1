# Install Current Tunnel as Windows Service
# This makes the tunnel run automatically (no manual intervention needed)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Install Tunnel as Windows Service" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  - Stop current tunnel process" -ForegroundColor White
Write-Host "  - Install tunnel as Windows service" -ForegroundColor White
Write-Host "  - Service runs automatically on startup" -ForegroundColor White
Write-Host "  - No manual intervention needed!" -ForegroundColor White
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ ERROR: This script requires Administrator privileges" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run PowerShell as Administrator:" -ForegroundColor Yellow
    Write-Host "  1. Right-click PowerShell" -ForegroundColor White
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor White
    Write-Host "  3. Run this script again" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "✅ Running as Administrator" -ForegroundColor Green
Write-Host ""

# Check if NSSM is available
$nssmPath = "C:\Tools\nssm\nssm.exe"
if (-not (Test-Path $nssmPath)) {
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssm) {
        $nssmPath = $nssm.Source
    } else {
        Write-Host "ERROR: NSSM not found" -ForegroundColor Red
        Write-Host "Please install NSSM first:" -ForegroundColor Yellow
        Write-Host "  winget install --id NSSM.NSSM -e" -ForegroundColor White
        exit 1
    }
}

# Check if cloudflared is available
$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
    Write-Host "ERROR: cloudflared not found" -ForegroundColor Red
    Write-Host "Please install cloudflared:" -ForegroundColor Yellow
    Write-Host "  winget install --id Cloudflare.cloudflared -e" -ForegroundColor White
    exit 1
}

$serviceName = "NavixyQuickTunnel"
$serviceDisplayName = "Navixy Quick Tunnel (Cloudflare)"

# Stop current tunnel process if running
Write-Host "Stopping current tunnel process..." -ForegroundColor Yellow
Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object {
    $cmd = (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
    $cmd -like "*--url*"
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Check if service already exists
$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Service '$serviceName' already exists" -ForegroundColor Yellow
    Write-Host "Removing existing service..." -ForegroundColor Yellow
    
    # Stop and remove existing service
    if ($existingService.Status -eq 'Running') {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    
    & $nssmPath remove $serviceName confirm 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Installing service..." -ForegroundColor Green

# Get cloudflared path
$cloudflaredPath = (Get-Command cloudflared).Source

# Install service
& $nssmPath install $serviceName $cloudflaredPath 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install service" -ForegroundColor Red
    exit 1
}

# Configure service
Write-Host "Configuring service..." -ForegroundColor Yellow

# Set arguments (port 8765)
& $nssmPath set $serviceName AppParameters "tunnel --url http://127.0.0.1:8765" 2>&1 | Out-Null

# Set display name
& $nssmPath set $serviceName DisplayName $serviceDisplayName 2>&1 | Out-Null

# Set description
& $nssmPath set $serviceName Description "Cloudflare Quick Tunnel for Navixy Live Map API (bypasses DNS, runs automatically)" 2>&1 | Out-Null

# Set startup type to automatic
& $nssmPath set $serviceName Start SERVICE_AUTO_START 2>&1 | Out-Null

# Set working directory
$workingDir = Split-Path -Parent $cloudflaredPath
& $nssmPath set $serviceName AppDirectory $workingDir 2>&1 | Out-Null

# Set output files
$logDir = Join-Path $scriptRoot "service\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$stdoutFile = Join-Path $logDir "quick_tunnel_stdout.log"
$stderrFile = Join-Path $logDir "quick_tunnel_stderr.log"

& $nssmPath set $serviceName AppStdout $stdoutFile 2>&1 | Out-Null
& $nssmPath set $serviceName AppStderr $stderrFile 2>&1 | Out-Null

# Set restart options
& $nssmPath set $serviceName AppRestartDelay 5000 2>&1 | Out-Null
& $nssmPath set $serviceName AppExit Default Restart 2>&1 | Out-Null

Write-Host "✅ Service installed successfully!" -ForegroundColor Green
Write-Host ""

# Start service
Write-Host "Starting service..." -ForegroundColor Yellow
Start-Service -Name $serviceName -ErrorAction Stop

Write-Host "✅ Service started!" -ForegroundColor Green
Write-Host ""

# Wait for tunnel to establish and get URL
Write-Host "Waiting for tunnel to establish (30 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Read log to find URL
$tunnelUrl = $null
$logContent = Get-Content $stdoutFile -ErrorAction SilentlyContinue
if (-not $logContent) {
    $logContent = Get-Content $stderrFile -ErrorAction SilentlyContinue
}

foreach ($line in $logContent) {
    if ($line -match 'https://([a-z0-9-]+)\.trycloudflare\.com') {
        $tunnelUrl = $matches[0]
        break
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($tunnelUrl) {
    $dataUrl = "$tunnelUrl/data"
    Write-Host "✅ Tunnel Service Running!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
    Write-Host "Data URL:  $dataUrl" -ForegroundColor Cyan
    Write-Host ""
    
    # Save URL to file
    $urlFile = Join-Path $scriptRoot ".quick_tunnel_url.txt"
    Set-Content -Path $urlFile -Value $dataUrl -Encoding UTF8
    Write-Host "✅ URL saved to: .quick_tunnel_url.txt" -ForegroundColor Green
    
    # Update index.html
    Write-Host ""
    Write-Host "Updating index.html..." -ForegroundColor Yellow
    $indexPath = Join-Path $scriptRoot "index.html"
    $content = Get-Content $indexPath -Raw
    $content = $content -replace '(?s)const\s+LIVE_API_URL\s*=\s*".*?";', "const LIVE_API_URL = `"$dataUrl`";"
    Set-Content -Path $indexPath -Value $content -Encoding UTF8
    Write-Host "✅ index.html updated" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Next: Push to GitHub" -ForegroundColor Yellow
    Write-Host "  git add index.html" -ForegroundColor White
    Write-Host "  git commit -m 'Update to service tunnel URL'" -ForegroundColor White
    Write-Host "  git push" -ForegroundColor White
} else {
    Write-Host "⚠️  Tunnel URL not found in logs yet" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The service is running, but URL may need more time" -ForegroundColor Yellow
    Write-Host "Check logs: $stdoutFile" -ForegroundColor White
    Write-Host ""
    Write-Host "To get URL manually:" -ForegroundColor Yellow
    Write-Host "  Get-Content `"$stdoutFile`" | Select-String `"trycloudflare`"" -ForegroundColor White
}

Write-Host ""
Write-Host "Service Status:" -ForegroundColor Cyan
Get-Service -Name $serviceName | Format-Table -AutoSize Name, Status, StartType
Write-Host ""
Write-Host "✅ Service will run automatically on startup!" -ForegroundColor Green
Write-Host "✅ No manual intervention needed!" -ForegroundColor Green
Write-Host ""
