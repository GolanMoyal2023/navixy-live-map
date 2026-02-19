# Sync and deploy Navixy Live Map to GitHub Pages
# Run from repo root (D:\2Plus\Services\navixy-live-map). Adds index.html, config.js, llbg_layers.geojson, Pictures, then commits and pushes.

$ErrorActionPreference = "Stop"

$repoPath = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { Get-Location }
$repoPath = $repoPath.TrimEnd("\")

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Sync to GitHub Pages (navixy-live-map)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$indexFile = Join-Path $repoPath "index.html"
if (-not (Test-Path $indexFile)) {
    Write-Host "ERROR: index.html not found at $indexFile" -ForegroundColor Red
    exit 1
}

# Production API is set via config.js (window.NAVIXY_MAP_API_BASE)
$configFile = Join-Path $repoPath "config.js"
if (Test-Path $configFile) {
    Write-Host "Using config.js for API base (production)" -ForegroundColor Green
} else {
    Write-Host "WARNING: config.js not found; copy config.js.example to config.js and set API base for production." -ForegroundColor Yellow
}

Write-Host "Repository: $repoPath" -ForegroundColor Cyan
Write-Host "Files: index.html, config.js, llbg_layers.geojson, Pictures/" -ForegroundColor Cyan
Write-Host ""

Push-Location $repoPath

try {
    & git add index.html, config.js, llbg_layers.geojson 2>$null
    if (Test-Path (Join-Path $repoPath "Pictures")) {
        & git add Pictures/ 2>$null
    }
    $status = & git status --short 2>&1
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "No changes to deploy." -ForegroundColor Green
        Pop-Location
        exit 0
    }
    Write-Host "Staged changes:" -ForegroundColor Yellow
    & git status --short
    Write-Host ""
    $commitMsg = "Sync map to GitHub Pages: index, config, layers, pictures"
    & git commit -m $commitMsg 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Nothing to commit or commit failed." -ForegroundColor Yellow
        Pop-Location
        exit 0
    }
    Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
    & git push 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Deployment successful" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Live URL: https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
        Write-Host "Changes may take a few minutes; hard refresh (Ctrl+Shift+R) if needed." -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: git push failed. Check remote and auth." -ForegroundColor Red
        Pop-Location
        exit 1
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
} finally {
    Pop-Location
}
