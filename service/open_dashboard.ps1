# Open Dashboard in Browser
# Waits for dashboard to be ready, then opens browser

$ErrorActionPreference = "Continue"

$dashboardUrl = "http://127.0.0.1:8766"
$maxAttempts = 30
$attempt = 0

Write-Host "Waiting for dashboard to be ready..." -ForegroundColor Yellow

while ($attempt -lt $maxAttempts) {
    try {
        $response = Invoke-WebRequest -Uri "$dashboardUrl/api/status" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ Dashboard is ready!" -ForegroundColor Green
            Start-Sleep -Seconds 1
            Start-Process $dashboardUrl
            Write-Host "✅ Browser opened: $dashboardUrl" -ForegroundColor Green
            exit 0
        }
    } catch {
        # Dashboard not ready yet
    }
    
    $attempt++
    Start-Sleep -Seconds 1
}

Write-Host "⚠️  Dashboard not ready after $maxAttempts seconds" -ForegroundColor Yellow
Write-Host "Opening dashboard URL anyway..." -ForegroundColor Yellow
Start-Process $dashboardUrl
