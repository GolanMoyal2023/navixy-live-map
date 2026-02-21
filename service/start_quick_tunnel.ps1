# Start Cloudflare Quick Tunnel as Background Service
# This bypasses DNS and provides immediate public access

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\env.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting Cloudflare Quick Tunnel" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "This tunnel bypasses DNS - no DNS configuration needed!" -ForegroundColor Green
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

# Check if already running
$existing = Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object {
    $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
    $cmdLine -like "*tunnel*" -and $cmdLine -like "*--url*"
}

if ($existing) {
    Write-Host "Quick tunnel already running (PID: $($existing.Id))" -ForegroundColor Yellow
    Write-Host "To restart, stop the existing process first" -ForegroundColor Yellow
    exit 0
}

Write-Host "Starting quick tunnel..." -ForegroundColor Green
Write-Host "This will create a public URL that works immediately" -ForegroundColor Cyan
Write-Host ""

# Start tunnel - it will output the URL
# We'll capture it and update index.html
$outputFile = Join-Path $PSScriptRoot "..\quick_tunnel_output.txt"
$errorFile = Join-Path $PSScriptRoot "..\quick_tunnel_error.txt"

$tunnelProcess = Start-Process -FilePath "cloudflared" `
    -ArgumentList "tunnel", "--url", "http://127.0.0.1:$env:PORT" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput $outputFile `
    -RedirectStandardError $errorFile

Write-Host "Tunnel process started (PID: $($tunnelProcess.Id))" -ForegroundColor Green
Write-Host "Waiting for tunnel URL..." -ForegroundColor Yellow
Start-Sleep -Seconds 12

# Read output to find URL
$tunnelUrl = $null
$output = Get-Content $outputFile -ErrorAction SilentlyContinue
$errorOutput = Get-Content $errorFile -ErrorAction SilentlyContinue

$allOutput = @()
if ($output) { $allOutput += $output }
if ($errorOutput) { $allOutput += $errorOutput }

foreach ($line in $allOutput) {
    if ($line -match 'https://([a-z0-9-]+)\.trycloudflare\.com') {
        $tunnelUrl = $matches[0]
        break
    }
}

if ($tunnelUrl) {
    $dataUrl = "$tunnelUrl/data"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "✅ Tunnel URL Created!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
    Write-Host "Data URL:  $dataUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  IMPORTANT: Keep this process running!" -ForegroundColor Yellow
    Write-Host "   Process ID: $($tunnelProcess.Id)" -ForegroundColor White
    Write-Host ""
    Write-Host "This URL works immediately - no DNS needed!" -ForegroundColor Green
    
    # Save URL to file for reference
    $urlFile = Join-Path $PSScriptRoot "..\.quick_tunnel_url.txt"
    Set-Content -Path $urlFile -Value $dataUrl -Encoding UTF8
    
    Write-Host ""
    Write-Host "To update index.html with this URL, run:" -ForegroundColor Yellow
    Write-Host "  cd `"$PSScriptRoot\..`"" -ForegroundColor White
    Write-Host "  .\update_index_with_tunnel_url.ps1" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "⚠️  Could not extract tunnel URL from output" -ForegroundColor Yellow
    Write-Host "Tunnel is running, but URL not found in output" -ForegroundColor Yellow
    Write-Host "Check the output files:" -ForegroundColor Yellow
    Write-Host "  $outputFile" -ForegroundColor White
    Write-Host "  $errorFile" -ForegroundColor White
    Write-Host ""
    Write-Host "You can manually check the tunnel output for the URL" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Tunnel is running in background..." -ForegroundColor Green
Write-Host "To stop: Stop-Process -Id $($tunnelProcess.Id)" -ForegroundColor Gray
