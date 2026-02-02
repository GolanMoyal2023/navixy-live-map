# Setup Public Access for Navixy Live Map
# Creates a Cloudflare Quick Tunnel for immediate external access

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setting Up Public Access" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$navixyMapPath = "D:\New_Recovery\2Plus\navixy-live-map"
$indexPath = Join-Path $navixyMapPath "index.html"

# Check if cloudflared is available
$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
    Write-Host "ERROR: cloudflared not found" -ForegroundColor Red
    Write-Host "Installing cloudflared..." -ForegroundColor Yellow
    winget install --id Cloudflare.cloudflared -e
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to install cloudflared" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Starting Cloudflare Quick Tunnel..." -ForegroundColor Yellow
Write-Host "This will create a temporary public URL" -ForegroundColor Yellow
Write-Host ""

# Start quick tunnel in background and capture URL
$tunnelProcess = Start-Process -FilePath "cloudflared" -ArgumentList "tunnel", "--url", "http://127.0.0.1:8765" -NoNewWindow -PassThru -RedirectStandardOutput "tunnel_output.txt" -RedirectStandardError "tunnel_error.txt"

Start-Sleep -Seconds 5

# Read tunnel output to find URL
$tunnelOutput = Get-Content "tunnel_output.txt" -ErrorAction SilentlyContinue
$tunnelError = Get-Content "tunnel_error.txt" -ErrorAction SilentlyContinue

$tunnelUrl = $null
if ($tunnelOutput) {
    foreach ($line in $tunnelOutput) {
        if ($line -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $tunnelUrl = $matches[0]
            break
        }
    }
}

if (-not $tunnelUrl -and $tunnelError) {
    foreach ($line in $tunnelError) {
        if ($line -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $tunnelUrl = $matches[0]
            break
        }
    }
}

if ($tunnelUrl) {
    $dataUrl = "$tunnelUrl/data"
    Write-Host "Tunnel URL found: $tunnelUrl" -ForegroundColor Green
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
    
    & git add index.html
    & git commit -m "Update API URL to Cloudflare tunnel" 2>&1 | Out-Null
    & git push 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GitHub Pages updated!" -ForegroundColor Green
    } else {
        Write-Host "Git push may have failed. Check manually." -ForegroundColor Yellow
    }
    
    Pop-Location
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Setup Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Public URL: $dataUrl" -ForegroundColor Cyan
    Write-Host "GitHub Pages: https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Note: Keep the tunnel process running!" -ForegroundColor Yellow
    Write-Host "The tunnel URL is temporary and will change if restarted." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "For permanent access, configure DNS nameservers at registrar." -ForegroundColor Cyan
} else {
    Write-Host "ERROR: Could not get tunnel URL" -ForegroundColor Red
    Write-Host "Tunnel output:" -ForegroundColor Yellow
    if ($tunnelOutput) { Write-Host $tunnelOutput }
    if ($tunnelError) { Write-Host $tunnelError }
    Stop-Process -Id $tunnelProcess.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
