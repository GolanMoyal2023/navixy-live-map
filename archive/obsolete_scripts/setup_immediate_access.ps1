# Setup Immediate Access with Quick Tunnel
# Creates a temporary tunnel URL that works immediately (no DNS needed)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setting Up Immediate Access" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will create a temporary tunnel URL that works immediately" -ForegroundColor Yellow
Write-Host "No DNS configuration needed!" -ForegroundColor Green
Write-Host ""

$navixyMapPath = "D:\New_Recovery\2Plus\navixy-live-map"
$indexPath = Join-Path $navixyMapPath "index.html"

# Check if API server is running
Write-Host "Checking API server..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 3
    Write-Host " API server is running" -ForegroundColor Green
} catch {
    Write-Host " API server not responding on port 8765" -ForegroundColor Red
    Write-Host "Please start the NavixyApi service first" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Starting Cloudflare Quick Tunnel..." -ForegroundColor Yellow
Write-Host "This will create a temporary public URL..." -ForegroundColor Cyan
Write-Host ""

# Start quick tunnel and capture output
$outputFile = Join-Path $navixyMapPath "quick_tunnel_output.txt"
$errorFile = Join-Path $navixyMapPath "quick_tunnel_error.txt"

$tunnelProcess = Start-Process -FilePath "cloudflared" `
    -ArgumentList "tunnel", "--url", "http://127.0.0.1:8765" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput $outputFile `
    -RedirectStandardError $errorFile

Write-Host "Waiting for tunnel URL..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

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

if (-not $tunnelUrl) {
    Write-Host " Could not get tunnel URL" -ForegroundColor Red
    Write-Host "Tunnel output:" -ForegroundColor Yellow
    if ($output) { $output | Select-Object -First 10 }
    if ($errorOutput) { $errorOutput | Select-Object -First 10 }
    Write-Host ""
    Write-Host "You can manually start the tunnel:" -ForegroundColor Yellow
    Write-Host "  cloudflared tunnel --url http://127.0.0.1:8765" -ForegroundColor White
    Write-Host "Then copy the URL and update index.html manually" -ForegroundColor Yellow
    Stop-Process -Id $tunnelProcess.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

$dataUrl = "$tunnelUrl/data"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Tunnel URL Found!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
Write-Host "Data URL:   $dataUrl" -ForegroundColor Cyan
Write-Host ""

# Update index.html
Write-Host "Updating index.html..." -ForegroundColor Yellow
$content = Get-Content $indexPath -Raw
$content = $content -replace '(?s)const\s+LIVE_API_URL\s*=\s*".*?";', "const LIVE_API_URL = `"$dataUrl`";"
Set-Content -Path $indexPath -Value $content -Encoding UTF8
Write-Host " index.html updated" -ForegroundColor Green
Write-Host ""

# Push to GitHub
Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
Push-Location $navixyMapPath

try {
    & git add index.html 2>&1 | Out-Null
    $commitMsg = "Use quick tunnel URL for immediate access ($tunnelUrl)"
    & git commit -m $commitMsg 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        & git push 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host " Pushed to GitHub successfully!" -ForegroundColor Green
        } else {
            Write-Host "  Git push may have failed (authentication?)" -ForegroundColor Yellow
            Write-Host "You can push manually: git push" -ForegroundColor White
        }
    } else {
        Write-Host "  Git commit failed" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Git operations failed: $_" -ForegroundColor Yellow
    Write-Host "You can push manually:" -ForegroundColor Yellow
    Write-Host "  git add index.html" -ForegroundColor White
    Write-Host "  git commit -m 'Update API URL'" -ForegroundColor White
    Write-Host "  git push" -ForegroundColor White
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  IMPORTANT: Keep the tunnel running!" -ForegroundColor Yellow
Write-Host "   Process ID: $($tunnelProcess.Id)" -ForegroundColor White
Write-Host "   To stop: Stop-Process -Id $($tunnelProcess.Id)" -ForegroundColor White
Write-Host ""
Write-Host " GitHub Pages URL:" -ForegroundColor Cyan
Write-Host "   https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
Write-Host ""
Write-Host " API URL:" -ForegroundColor Cyan
Write-Host "   $dataUrl" -ForegroundColor White
Write-Host ""
