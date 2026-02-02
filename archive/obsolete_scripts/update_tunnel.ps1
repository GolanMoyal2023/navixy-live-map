param(
    [string]$LocalUrl = "http://127.0.0.1:8080",
    [string]$IndexPath = "",
    [switch]$UpdateGitHub = $true
)

$ErrorActionPreference = "Stop"

Write-Host "DEBUG: update_tunnel.ps1 v2026-01-31-1" -ForegroundColor Yellow

# Auto-detect index.html path if not provided
if ([string]::IsNullOrEmpty($IndexPath)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $IndexPath = Join-Path $scriptRoot "index.html"
}

Write-Host "Starting localtunnel for $LocalUrl" -ForegroundColor Cyan
Write-Host "This will keep running until you stop it (Ctrl+C)." -ForegroundColor Yellow

$root = Split-Path -Parent $IndexPath

if (-not (Test-Path -Path $IndexPath)) {
    Write-Host "ERROR: index.html not found at $IndexPath" -ForegroundColor Red
    exit 1
}

$urlFound = $false

$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $port = ([System.Uri]$LocalUrl).Port
    & npx localtunnel --port $port 2>&1 | ForEach-Object {
    $line = $_.ToString()
        Write-Host $line

    $tunnelMatch = [regex]::Match($line, 'https://\S+\.loca\.lt')
    if (-not $urlFound -and $tunnelMatch.Success) {
        $tunnelUrl = $tunnelMatch.Value
            $dataUrl = "$tunnelUrl/data"

        Write-Host "DEBUG: URL match detected." -ForegroundColor Yellow
            Write-Host "Detected tunnel URL: $tunnelUrl" -ForegroundColor Green
            Write-Host "Updating index.html -> $dataUrl" -ForegroundColor Green

        $content = Get-Content -Path $IndexPath -Raw
        $content = $content -replace '(?s)const\s+LIVE_API_URL\s*=\s*".*?";', "const LIVE_API_URL = `"$dataUrl`";"
            Set-Content -Path $IndexPath -Value $content -Encoding UTF8

        $lastPath = Join-Path $root ".last_tunnel_url.txt"
        Write-Host "DEBUG: Writing last URL -> $lastPath" -ForegroundColor Yellow
        Set-Content -Path $lastPath -Value $dataUrl -Encoding UTF8
            $urlFound = $true

            if ($UpdateGitHub) {
                $repoRoot = Split-Path -Path $IndexPath -Parent
                Write-Host "Updating GitHub Pages (git add/commit/push)..." -ForegroundColor Cyan

                $status = & git -c safe.directory=$repoRoot -C $repoRoot status --porcelain 2>&1
                if (-not $status) {
                    Write-Host "No changes to commit." -ForegroundColor Yellow
                } else {
                    & git -c safe.directory=$repoRoot -C $repoRoot add $IndexPath | Out-Null
                    $commitMsg = "Update live API URL"
                    & git -c safe.directory=$repoRoot -C $repoRoot commit -m $commitMsg | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "Git commit failed. Check git status." -ForegroundColor Red
                        return
                    }
                    & git -c safe.directory=$repoRoot -C $repoRoot push | Out-Null
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
} finally {
    $ErrorActionPreference = $prevErrorAction
}

Write-Host "Tunnel process ended." -ForegroundColor Yellow
