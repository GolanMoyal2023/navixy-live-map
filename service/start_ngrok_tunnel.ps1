# Start Ngrok tunnel for Navixy Live Map API (no Cloudflare wait / rate limit)
# Exposes local API (port 8767) to a public URL and updates api-url.json for mobile/GitHub Pages.
# Usage: .\service\start_ngrok_tunnel.ps1 [ -Push ]
#   -Push  Update api-url.json and push to GitHub so phone can use the map.

param([switch]$Push)

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }
$root = $root.TrimEnd("\")

# Port to expose (Navixy API from start_all.ps1)
$localPort = 8767

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Ngrok tunnel for Navixy Live Map" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Local: http://127.0.0.1:$localPort" -ForegroundColor Yellow
Write-Host ""

$ngrok = Get-Command ngrok -ErrorAction SilentlyContinue
if (-not $ngrok) {
    Write-Host "ERROR: ngrok not found in PATH" -ForegroundColor Red
    Write-Host "Install: winget install --id Ngrok.Ngrok -e" -ForegroundColor Yellow
    exit 1
}

# Check if ngrok is already running (local API on 4040)
$existing = $null
try {
    $existing = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2 -ErrorAction Stop
} catch { }

if ($existing -and $existing.tunnels -and $existing.tunnels.Count -gt 0) {
    $first = $existing.tunnels | Where-Object { $_.public_url -match "^https://" } | Select-Object -First 1
    if ($first) {
        $baseUrl = $first.public_url.TrimEnd("/")
        $dataUrl = "$baseUrl/data"
        Write-Host "Ngrok already running: $dataUrl" -ForegroundColor Green
        $urlFile = Join-Path $root ".quick_tunnel_url.txt"
        $apiUrlFile = Join-Path $root "api-url.json"
        $dataUrl | Out-File -FilePath $urlFile -Encoding UTF8 -NoNewline
        @{ dataUrl = $dataUrl } | ConvertTo-Json -Compress | Set-Content -Path $apiUrlFile -Encoding UTF8 -NoNewline
        Write-Host "Updated .quick_tunnel_url.txt and api-url.json" -ForegroundColor Green
        if ($Push) {
            Push-Location $root
            git add api-url.json 2>$null; git commit -m "Update public API URL (Ngrok) for mobile" 2>&1; git push 2>&1
            Pop-Location
            Write-Host "Pushed to GitHub. Open map on phone in 1-2 min." -ForegroundColor Green
        }
        exit 0
    }
}

Write-Host "Starting ngrok http $localPort ..." -ForegroundColor Green
$proc = Start-Process -FilePath "ngrok" -ArgumentList "http", $localPort -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 5

$tunnels = $null
try {
    $tunnels = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 5
} catch {
    Write-Host "ERROR: Could not get tunnel URL from ngrok API (http://127.0.0.1:4040)" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

$first = $tunnels.tunnels | Where-Object { $_.public_url -match "^https://" } | Select-Object -First 1
if (-not $first) {
    Write-Host "ERROR: No HTTPS tunnel URL in ngrok response" -ForegroundColor Red
    exit 1
}

$baseUrl = $first.public_url.TrimEnd("/")
$dataUrl = "$baseUrl/data"

$urlFile = Join-Path $root ".quick_tunnel_url.txt"
$apiUrlFile = Join-Path $root "api-url.json"
$dataUrl | Out-File -FilePath $urlFile -Encoding UTF8 -NoNewline
@{ dataUrl = $dataUrl } | ConvertTo-Json -Compress | Set-Content -Path $apiUrlFile -Encoding UTF8 -NoNewline

Write-Host ""
Write-Host "Tunnel URL: $dataUrl" -ForegroundColor Cyan
Write-Host "Updated .quick_tunnel_url.txt and api-url.json" -ForegroundColor Green
Write-Host "Keep ngrok running. To update GitHub for phone:" -ForegroundColor Yellow
Write-Host "  .\service\update_public_url_from_tunnel.ps1 -Push" -ForegroundColor White
if ($Push) {
    Push-Location $root
    git add api-url.json 2>$null; git commit -m "Update public API URL (Ngrok) for mobile" 2>&1; git push 2>&1
    Pop-Location
    Write-Host "Pushed to GitHub. Open https://golanmoyal2023.github.io/navixy-live-map/ on phone in 1-2 min." -ForegroundColor Green
}
