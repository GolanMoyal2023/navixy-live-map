# Start Cloudflare Tunnel as Background Service
# This keeps the tunnel running continuously

$ErrorActionPreference = "Continue"

$tunnelUrl = "https://obviously-publishers-noon-values.trycloudflare.com"
$localPort = "8765"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting Cloudflare Tunnel Service" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if already running
$existing = Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object { 
    $_.CommandLine -like "*tunnel*" -or 
    (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -like "*tunnel*"
}

if ($existing) {
    Write-Host "Tunnel already running (PID: $($existing.Id))" -ForegroundColor Yellow
    Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To restart, stop the process first:" -ForegroundColor Yellow
    Write-Host "  Stop-Process -Id $($existing.Id) -Force" -ForegroundColor White
    exit 0
}

Write-Host "Starting tunnel..." -ForegroundColor Green
Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
Write-Host "Local service: http://127.0.0.1:$localPort" -ForegroundColor Cyan
Write-Host ""

# Start tunnel in background
$process = Start-Process -FilePath "cloudflared" -ArgumentList "tunnel", "--url", "http://127.0.0.1:$localPort" -WindowStyle Hidden -PassThru

Start-Sleep -Seconds 8

if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
    Write-Host "Tunnel started successfully!" -ForegroundColor Green
    Write-Host "Process ID: $($process.Id)" -ForegroundColor Cyan
    Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Tunnel is running in background" -ForegroundColor Green
    Write-Host ""
    Write-Host "To stop: Stop-Process -Id $($process.Id) -Force" -ForegroundColor Gray
    
    # Save process info
    @{
        ProcessId = $process.Id
        TunnelUrl = $tunnelUrl
        StartTime = Get-Date
    } | ConvertTo-Json | Set-Content ".tunnel_info.json"
} else {
    Write-Host "ERROR: Tunnel failed to start" -ForegroundColor Red
    exit 1
}
