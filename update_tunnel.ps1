param(
    [string]$LocalUrl = "http://127.0.0.1:8765",
    [string]$IndexPath = "D:\New_Recovery\2Plus\navixy-live-map\index.html",
    [switch]$UpdateGitHub = $true
)

$ErrorActionPreference = "Stop"

Write-Host "Starting Quick Tunnel for $LocalUrl" -ForegroundColor Cyan
Write-Host "This will keep running until you stop it (Ctrl+C)." -ForegroundColor Yellow

if (-not (Test-Path -Path $IndexPath)) {
    Write-Host "ERROR: index.html not found at $IndexPath" -ForegroundColor Red
    exit 1
}

$cloudflaredArgs = @("tunnel", "--url", $LocalUrl, "--config", "NUL")

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = "cloudflared"
$startInfo.Arguments = ($cloudflaredArgs -join " ")
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo

[void]$process.Start()

$reader = $process.StandardOutput
$urlFound = $false

while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    Write-Host $line

    if (-not $urlFound -and $line -match "https://[a-z0-9\-]+\.trycloudflare\.com") {
        $tunnelUrl = $Matches[0]
        $dataUrl = "$tunnelUrl/data"

        Write-Host "Detected tunnel URL: $tunnelUrl" -ForegroundColor Green
        Write-Host "Updating index.html -> $dataUrl" -ForegroundColor Green

        $content = Get-Content -Path $IndexPath -Raw
        $content = $content -replace 'const LIVE_API_URL = ".*?";', "const LIVE_API_URL = `"$dataUrl`";"
        Set-Content -Path $IndexPath -Value $content -Encoding UTF8

        Set-Content -Path ".last_tunnel_url.txt" -Value $dataUrl -Encoding UTF8
        $urlFound = $true

        if ($UpdateGitHub) {
            $repoRoot = Split-Path -Path $IndexPath -Parent
            Write-Host "Updating GitHub Pages (git add/commit/push)..." -ForegroundColor Cyan

            $status = & git -C $repoRoot status --porcelain 2>&1
            if (-not $status) {
                Write-Host "No changes to commit." -ForegroundColor Yellow
            } else {
                & git -C $repoRoot add $IndexPath | Out-Null
                $commitMsg = "Update live API URL"
                & git -C $repoRoot commit -m $commitMsg | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Git commit failed. Check git status." -ForegroundColor Red
                    return
                }
                & git -C $repoRoot push | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Git push failed. Please login to GitHub and retry." -ForegroundColor Red
                    return
                }
                Write-Host "GitHub Pages updated." -ForegroundColor Green
                Write-Host "LIVE_API_URL pushed: $dataUrl" -ForegroundColor Green
            }
        }
    }
}

Write-Host "Tunnel process ended." -ForegroundColor Yellow
