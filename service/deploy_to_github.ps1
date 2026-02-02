# Deploy index.html to GitHub Pages
# Updates the production index.html and pushes to GitHub

$ErrorActionPreference = "Stop"

$repoPath = "D:\New_Recovery\2Plus\navixy-live-map"
$indexFile = Join-Path $repoPath "index.html"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying to GitHub Pages" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify index.html exists
if (-not (Test-Path $indexFile)) {
    Write-Host "ERROR: index.html not found at $indexFile" -ForegroundColor Red
    exit 1
}

# Verify API URL is correct
$content = Get-Content $indexFile -Raw
if ($content -notmatch 'const LIVE_API_URL = "https://navixy-livemap\.moyals\.net/data"') {
    Write-Host "WARNING: API URL might not be set correctly" -ForegroundColor Yellow
    Write-Host "Expected: https://navixy-livemap.moyals.net/data" -ForegroundColor Yellow
}

Write-Host "Repository: $repoPath" -ForegroundColor Cyan
Write-Host "File: index.html" -ForegroundColor Cyan
Write-Host ""

# Change to repo directory
Push-Location $repoPath

try {
    # Check git status
    Write-Host "Checking git status..." -ForegroundColor Yellow
    $status = & git status --porcelain index.html 2>&1
    
    if ($status -match "^\s*M\s+index\.html") {
        Write-Host "index.html has changes to commit" -ForegroundColor Green
    } elseif ($status -match "^\s*\?\?\s+index\.html") {
        Write-Host "index.html is untracked, will add" -ForegroundColor Yellow
    } elseif ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "No changes to index.html" -ForegroundColor Yellow
        Write-Host "File is already up to date" -ForegroundColor Green
        Pop-Location
        exit 0
    }
    
    # Add file
    Write-Host "Adding index.html..." -ForegroundColor Yellow
    & git add index.html 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: git add failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    
    # Commit
    Write-Host "Committing changes..." -ForegroundColor Yellow
    $commitMsg = "Update index.html with production API URL (navixy-livemap.moyals.net)"
    & git commit -m $commitMsg 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: git commit failed" -ForegroundColor Red
        Write-Host "This might mean there are no changes to commit" -ForegroundColor Yellow
        Pop-Location
        exit 1
    }
    
    Write-Host "Commit successful" -ForegroundColor Green
    Write-Host ""
    
    # Push
    Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
    & git push 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "✅ Deployment Successful!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "GitHub Pages URL:" -ForegroundColor Cyan
        Write-Host "https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
        Write-Host ""
        Write-Host "Note: It may take a few minutes for changes to appear" -ForegroundColor Yellow
        Write-Host "      Hard refresh (Ctrl+Shift+R) if needed" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "ERROR: git push failed" -ForegroundColor Red
        Write-Host "You may need to:" -ForegroundColor Yellow
        Write-Host "1. Check git remote: git remote -v" -ForegroundColor White
        Write-Host "2. Authenticate with GitHub" -ForegroundColor White
        Write-Host "3. Push manually: git push" -ForegroundColor White
        Pop-Location
        exit 1
    }
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
} finally {
    Pop-Location
}
