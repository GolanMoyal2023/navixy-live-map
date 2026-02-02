# Update index.html with Quick Tunnel URL
# Reads the tunnel URL from .quick_tunnel_url.txt and updates index.html

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$indexPath = Join-Path $scriptRoot "index.html"
$urlFile = Join-Path $scriptRoot ".quick_tunnel_url.txt"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Updating index.html with Tunnel URL" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if URL file exists
if (-not (Test-Path $urlFile)) {
    Write-Host "ERROR: Tunnel URL file not found: $urlFile" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please start the quick tunnel first:" -ForegroundColor Yellow
    Write-Host "  .\service\start_quick_tunnel.ps1" -ForegroundColor White
    exit 1
}

# Read tunnel URL
$dataUrl = Get-Content $urlFile -Raw | ForEach-Object { $_.Trim() }

if ([string]::IsNullOrWhiteSpace($dataUrl)) {
    Write-Host "ERROR: Tunnel URL file is empty" -ForegroundColor Red
    exit 1
}

Write-Host "Tunnel URL: $dataUrl" -ForegroundColor Cyan
Write-Host ""

# Update index.html
Write-Host "Updating index.html..." -ForegroundColor Yellow
$content = Get-Content $indexPath -Raw
$content = $content -replace '(?s)const\s+LIVE_API_URL\s*=\s*".*?";', "const LIVE_API_URL = `"$dataUrl`";"
Set-Content -Path $indexPath -Value $content -Encoding UTF8
Write-Host "✅ index.html updated" -ForegroundColor Green
Write-Host ""

# Ask if user wants to push to GitHub
Write-Host "Push to GitHub? (Y/N)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq 'Y' -or $response -eq 'y') {
    Write-Host ""
    Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
    Push-Location $scriptRoot
    
    try {
        & git add index.html 2>&1 | Out-Null
        $commitMsg = "Update API URL to Cloudflare quick tunnel (bypasses DNS)"
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
} else {
    Write-Host ""
    Write-Host "Skipping GitHub push. To push manually:" -ForegroundColor Yellow
    Write-Host "  git add index.html" -ForegroundColor White
    Write-Host "  git commit -m 'Update API URL'" -ForegroundColor White
    Write-Host "  git push" -ForegroundColor White
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ Update Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "GitHub Pages URL:" -ForegroundColor Cyan
Write-Host "  https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
Write-Host ""
Write-Host "⚠️  Remember: Keep the tunnel process running!" -ForegroundColor Yellow
Write-Host ""
