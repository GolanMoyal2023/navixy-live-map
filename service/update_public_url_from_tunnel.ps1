# Update api-url.json from .quick_tunnel_url.txt (Ngrok or any tunnel)
# Run after starting the tunnel so mobile/GitHub Pages uses the current URL.
# Optional: -Push to commit and push to GitHub (updates live map for mobile).

param([switch]$Push)

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }
$root = $root.TrimEnd("\")
$urlFile = Join-Path $root ".quick_tunnel_url.txt"
$apiUrlFile = Join-Path $root "api-url.json"

if (-not (Test-Path $urlFile)) {
    Write-Host "ERROR: .quick_tunnel_url.txt not found. Start the tunnel first:" -ForegroundColor Red
    Write-Host "  .\service\start_ngrok_tunnel.ps1   (Ngrok, no wait)" -ForegroundColor White
    exit 1
}

$dataUrl = (Get-Content $urlFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($dataUrl)) {
    Write-Host "ERROR: .quick_tunnel_url.txt is empty." -ForegroundColor Red
    exit 1
}

$json = @{ dataUrl = $dataUrl } | ConvertTo-Json -Compress
Set-Content -Path $apiUrlFile -Value $json -Encoding UTF8 -NoNewline
Write-Host "Updated api-url.json with: $dataUrl" -ForegroundColor Green

if ($Push) {
    Push-Location $root
    try {
        git add api-url.json
        git commit -m "Update public API URL (tunnel) for mobile" 2>&1
        git push 2>&1
        Write-Host "Pushed to GitHub. Mobile map will use this URL after refresh." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}
