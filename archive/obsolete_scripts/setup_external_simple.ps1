# Simple External Access Setup (No Admin Required)
# Starts quick tunnel, gets URL, updates index.html, pushes to GitHub

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Simple External Access Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Start Cloudflare quick tunnel" -ForegroundColor White
Write-Host "  2. Get tunnel URL" -ForegroundColor White
Write-Host "  3. Update index.html" -ForegroundColor White
Write-Host "  4. Push to GitHub" -ForegroundColor White
Write-Host ""

# Check if cloudflared is available
$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
    Write-Host "ERROR: cloudflared not found" -ForegroundColor Red
    Write-Host "Please install cloudflared:" -ForegroundColor Yellow
    Write-Host "  winget install --id Cloudflare.cloudflared -e" -ForegroundColor White
    exit 1
}

# Stop any existing quick tunnels
Write-Host "Stopping existing quick tunnels..." -ForegroundColor Yellow
Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object {
    $cmd = (Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
    $cmd -like "*--url*"
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Start quick tunnel
Write-Host ""
Write-Host "Starting Cloudflare quick tunnel..." -ForegroundColor Cyan
Write-Host "This will create a public URL (no DNS needed)" -ForegroundColor Yellow
Write-Host ""

$outputFile = Join-Path $scriptRoot "quick_tunnel_output.txt"
$errorFile = Join-Path $scriptRoot "quick_tunnel_error.txt"

# Remove old output files
Remove-Item $outputFile -ErrorAction SilentlyContinue
Remove-Item $errorFile -ErrorAction SilentlyContinue

$tunnelProcess = Start-Process -FilePath "cloudflared" `
    -ArgumentList "tunnel", "--url", "http://127.0.0.1:8765" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput $outputFile `
    -RedirectStandardError $errorFile

Write-Host "Tunnel process started (PID: $($tunnelProcess.Id))" -ForegroundColor Green
Write-Host "Waiting for tunnel URL (15 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

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
    Write-Host ""
    Write-Host "⚠️  Could not extract tunnel URL from output" -ForegroundColor Yellow
    Write-Host "Tunnel is running, but URL not found yet" -ForegroundColor Yellow
    Write-Host "Waiting 15 more seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
    # Try again
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
}

if (-not $tunnelUrl) {
    Write-Host ""
    Write-Host "❌ ERROR: Could not get tunnel URL" -ForegroundColor Red
    Write-Host "Tunnel process is running (PID: $($tunnelProcess.Id))" -ForegroundColor Yellow
    Write-Host "Check output files:" -ForegroundColor Yellow
    Write-Host "  $outputFile" -ForegroundColor White
    Write-Host "  $errorFile" -ForegroundColor White
    Write-Host ""
    Write-Host "You can manually check the tunnel output for the URL" -ForegroundColor Yellow
    Write-Host "Keep the tunnel process running!" -ForegroundColor Yellow
    exit 1
}

$dataUrl = "$tunnelUrl/data"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ Tunnel URL Found!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tunnel URL: $tunnelUrl" -ForegroundColor Cyan
Write-Host "Data URL:  $dataUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  IMPORTANT: Keep tunnel process running!" -ForegroundColor Yellow
Write-Host "   Process ID: $($tunnelProcess.Id)" -ForegroundColor White
Write-Host "   To stop: Stop-Process -Id $($tunnelProcess.Id)" -ForegroundColor Gray
Write-Host ""

# Save URL to file
$urlFile = Join-Path $scriptRoot ".quick_tunnel_url.txt"
Set-Content -Path $urlFile -Value $dataUrl -Encoding UTF8
Write-Host "✅ URL saved to: .quick_tunnel_url.txt" -ForegroundColor Green

# Update index.html
Write-Host ""
Write-Host "Updating index.html..." -ForegroundColor Cyan
$indexPath = Join-Path $scriptRoot "index.html"
$content = Get-Content $indexPath -Raw
$content = $content -replace '(?s)const\s+LIVE_API_URL\s*=\s*".*?";', "const LIVE_API_URL = `"$dataUrl`";"
Set-Content -Path $indexPath -Value $content -Encoding UTF8
Write-Host "✅ index.html updated" -ForegroundColor Green

# Push to GitHub
Write-Host ""
Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
Push-Location $scriptRoot
try {
    & git add index.html 2>&1 | Out-Null
    $commitMsg = "Update API URL to Cloudflare quick tunnel (external access)"
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
        Write-Host "⚠️  Git commit failed (no changes?)" -ForegroundColor Yellow
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
Write-Host "Tunnel URL: $dataUrl" -ForegroundColor Cyan
Write-Host "GitHub Pages: https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  CRITICAL: Keep tunnel process running!" -ForegroundColor Yellow
Write-Host "   Process ID: $($tunnelProcess.Id)" -ForegroundColor White
Write-Host "   If you close PowerShell, tunnel stops and external access breaks" -ForegroundColor Yellow
Write-Host ""
Write-Host "💡 To make it permanent (Windows service):" -ForegroundColor Cyan
Write-Host "   Run PowerShell as Administrator, then:" -ForegroundColor White
Write-Host "   .\setup_simple_external_access.ps1" -ForegroundColor White
Write-Host ""
