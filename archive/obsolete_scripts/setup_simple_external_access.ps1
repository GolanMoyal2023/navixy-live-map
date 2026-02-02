# Simple Setup: Local Webpage → External Data via Cloudflare Tunnel
# Complete automated setup for GitHub Pages + Cloudflare Tunnel

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Simple External Access Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Install quick tunnel as Windows service (persistent)" -ForegroundColor White
Write-Host "  2. Get tunnel URL" -ForegroundColor White
Write-Host "  3. Update index.html" -ForegroundColor White
Write-Host "  4. Push to GitHub" -ForegroundColor White
Write-Host ""

# Step 1: Install quick tunnel service
Write-Host "Step 1: Installing quick tunnel service..." -ForegroundColor Cyan
Push-Location (Join-Path $scriptRoot "service")
try {
    & .\install_quick_tunnel_service.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install service" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

# Step 2: Get tunnel URL
Write-Host ""
Write-Host "Step 2: Getting tunnel URL..." -ForegroundColor Cyan
$urlFile = Join-Path $scriptRoot ".quick_tunnel_url.txt"
Start-Sleep -Seconds 10  # Give tunnel more time

$tunnelUrl = $null
if (Test-Path $urlFile) {
    $tunnelUrl = Get-Content $urlFile -Raw | ForEach-Object { $_.Trim() }
}

if (-not $tunnelUrl) {
    # Try reading from log
    $logFile = Join-Path $scriptRoot "service\logs\quick_tunnel_stdout.log"
    $logContent = Get-Content $logFile -ErrorAction SilentlyContinue
    if (-not $logContent) {
        $logFile = Join-Path $scriptRoot "service\logs\quick_tunnel_stderr.log"
        $logContent = Get-Content $logFile -ErrorAction SilentlyContinue
    }
    
    foreach ($line in $logContent) {
        if ($line -match 'https://([a-z0-9-]+)\.trycloudflare\.com') {
            $tunnelUrl = "$($matches[0])/data"
            break
        }
    }
}

if (-not $tunnelUrl) {
    Write-Host "ERROR: Could not get tunnel URL" -ForegroundColor Red
    Write-Host "Please check service logs manually" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Tunnel URL: $tunnelUrl" -ForegroundColor Green

# Step 3: Update index.html
Write-Host ""
Write-Host "Step 3: Updating index.html..." -ForegroundColor Cyan
$indexPath = Join-Path $scriptRoot "index.html"
$content = Get-Content $indexPath -Raw
$content = $content -replace '(?s)const\s+LIVE_API_URL\s*=\s*".*?";', "const LIVE_API_URL = `"$tunnelUrl`";"
Set-Content -Path $indexPath -Value $content -Encoding UTF8
Write-Host "✅ index.html updated" -ForegroundColor Green

# Step 4: Push to GitHub
Write-Host ""
Write-Host "Step 4: Pushing to GitHub..." -ForegroundColor Cyan
Push-Location $scriptRoot
try {
    & git add index.html 2>&1 | Out-Null
    $commitMsg = "Update API URL to Cloudflare quick tunnel (persistent service)"
    & git commit -m $commitMsg 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        & git push 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Pushed to GitHub successfully!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Git push failed (authentication?)" -ForegroundColor Yellow
            Write-Host "You can push manually: git push" -ForegroundColor White
        }
    } else {
        Write-Host "⚠️  Git commit failed" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Git operations failed: $_" -ForegroundColor Yellow
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
Write-Host "GitHub Pages: https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Service is running automatically (Windows service)" -ForegroundColor Green
Write-Host "✅ Tunnel will restart automatically if it stops" -ForegroundColor Green
Write-Host "✅ No DNS configuration needed" -ForegroundColor Green
Write-Host ""
Write-Host "⚠️  Note: If service restarts, URL may change" -ForegroundColor Yellow
Write-Host "   Check logs: service\logs\quick_tunnel_stdout.log" -ForegroundColor White
Write-Host ""
