# Update GitHub Pages with Working Tunnel URL
# This script helps set up external access

param(
    [string]$TunnelUrl = ""
)

$ErrorActionPreference = "Stop"

$navixyMapPath = "D:\New_Recovery\2Plus\navixy-live-map"
$indexPath = Join-Path $navixyMapPath "index.html"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Update GitHub Pages for External Access" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# If no URL provided, try to get from Cloudflare tunnel
if ([string]::IsNullOrEmpty($TunnelUrl)) {
    Write-Host "Option 1: Use Cloudflare Quick Tunnel (Temporary)" -ForegroundColor Yellow
    Write-Host "Option 2: Use Named Tunnel URL (Requires DNS)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "For immediate access, we'll use a quick tunnel." -ForegroundColor Cyan
    Write-Host "Starting Cloudflare quick tunnel..." -ForegroundColor Yellow
    
    # Start tunnel and capture URL
    $job = Start-Job -ScriptBlock {
        & cloudflared tunnel --url http://127.0.0.1:8765 2>&1
    }
    
    Start-Sleep -Seconds 8
    
    $output = Receive-Job -Job $job
    Stop-Job -Job $job
    Remove-Job -Job $job
    
    # Extract URL from output
    foreach ($line in $output) {
        if ($line -match 'https://([a-z0-9-]+)\.trycloudflare\.com') {
            $TunnelUrl = $matches[0]
            break
        }
    }
    
    if ([string]::IsNullOrEmpty($TunnelUrl)) {
        Write-Host "ERROR: Could not get tunnel URL automatically" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please run manually:" -ForegroundColor Yellow
        Write-Host "  cloudflared tunnel --url http://127.0.0.1:8765" -ForegroundColor White
        Write-Host ""
        Write-Host "Then provide the URL:" -ForegroundColor Yellow
        Write-Host "  .\update_github_with_tunnel.ps1 -TunnelUrl 'https://xxxxx.trycloudflare.com'" -ForegroundColor White
        exit 1
    }
}

$dataUrl = "$TunnelUrl/data"

Write-Host "Tunnel URL: $TunnelUrl" -ForegroundColor Green
Write-Host "Data URL: $dataUrl" -ForegroundColor Green
Write-Host ""

# Update index.html
Write-Host "Updating index.html..." -ForegroundColor Yellow
$content = Get-Content $indexPath -Raw
$content = $content -replace '(?s)const\s+LIVE_API_URL\s*=\s*".*?";', "const LIVE_API_URL = `"$dataUrl`";"
Set-Content -Path $indexPath -Value $content -Encoding UTF8
Write-Host "index.html updated" -ForegroundColor Green
Write-Host ""

# Update GitHub
Write-Host "Updating GitHub Pages..." -ForegroundColor Yellow
Push-Location $navixyMapPath

& git add index.html 2>&1 | Out-Null
& git commit -m "Update API URL for external access" 2>&1 | Out-Null
& git push 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "GitHub Pages updated successfully!" -ForegroundColor Green
} else {
    Write-Host "Git push may have failed. Please check manually." -ForegroundColor Yellow
    Write-Host "You can manually push:" -ForegroundColor Yellow
    Write-Host "  git add index.html" -ForegroundColor White
    Write-Host "  git commit -m 'Update API URL'" -ForegroundColor White
    Write-Host "  git push" -ForegroundColor White
}

Pop-Location

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Public Access:" -ForegroundColor Cyan
Write-Host "  GitHub Pages: https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
Write-Host "  API URL: $dataUrl" -ForegroundColor White
Write-Host ""
Write-Host "Important:" -ForegroundColor Yellow
Write-Host "  - Keep the Cloudflare tunnel running" -ForegroundColor Yellow
Write-Host "  - The tunnel URL is temporary (changes on restart)" -ForegroundColor Yellow
Write-Host "  - For permanent access, configure DNS nameservers" -ForegroundColor Yellow
Write-Host ""
