# Keep Cloudflare Tunnel Running
# Run this to ensure the tunnel stays active

$ErrorActionPreference = "Continue"

$tunnelUrl = "https://financing-maiden-becoming-tiny.trycloudflare.com"
$localPort = "8765"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cloudflare Tunnel Manager" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if tunnel process is already running
$existingTunnel = Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*tunnel*" -or $_.Path -like "*cloudflared*" }

if ($existingTunnel) {
    Write-Host "Tunnel process found (PID: $($existingTunnel.Id))" -ForegroundColor Yellow
    Write-Host "Checking if it's responding..." -ForegroundColor Yellow
    
    try {
        $response = Invoke-WebRequest -Uri "$tunnelUrl/health" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "Tunnel is working!" -ForegroundColor Green
            Write-Host "URL: $tunnelUrl" -ForegroundColor Cyan
            exit 0
        }
    } catch {
        Write-Host "Tunnel process exists but not responding" -ForegroundColor Yellow
        Write-Host "Restarting..." -ForegroundColor Yellow
        Stop-Process -Id $existingTunnel.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Starting Cloudflare tunnel..." -ForegroundColor Green
Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
Write-Host "Local service: http://127.0.0.1:$localPort" -ForegroundColor Cyan
Write-Host ""

# Start tunnel in background
$tunnelProcess = Start-Process -FilePath "cloudflared" -ArgumentList "tunnel", "--url", "http://127.0.0.1:$localPort" -NoNewWindow -PassThru

Start-Sleep -Seconds 8

# Verify it's running
if (Get-Process -Id $tunnelProcess.Id -ErrorAction SilentlyContinue) {
    Write-Host "Tunnel started successfully!" -ForegroundColor Green
    Write-Host "Process ID: $($tunnelProcess.Id)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Yellow
    Write-Host "Keep this process running!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To stop: Stop-Process -Id $($tunnelProcess.Id)" -ForegroundColor Gray
} else {
    Write-Host "ERROR: Tunnel process failed to start" -ForegroundColor Red
    exit 1
}
