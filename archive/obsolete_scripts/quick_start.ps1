# Quick Start Script for Navixy Live Map
# Starts the API server with proper environment setup

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Navixy Live Map - Quick Start" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load environment variables
$envScript = Join-Path $scriptRoot "service\env.ps1"
if (Test-Path $envScript) {
    Write-Host "Loading environment from env.ps1..." -ForegroundColor Yellow
    . $envScript
} else {
    Write-Host "⚠ env.ps1 not found!" -ForegroundColor Yellow
    Write-Host "Creating template..." -ForegroundColor Yellow
    $envDir = Split-Path $envScript
    if (-not (Test-Path $envDir)) {
        New-Item -ItemType Directory -Path $envDir -Force | Out-Null
    }
    @"
`$env:NAVIXY_API_HASH = "YOUR_NAVIXY_API_HASH_HERE"
`$env:PORT = "8080"
"@ | Set-Content $envScript -Encoding UTF8
    Write-Host "Template created. Please update with your API key!" -ForegroundColor Red
    Write-Host "File: $envScript" -ForegroundColor Yellow
    exit 1
}

# Check if API key is set
if (-not $env:NAVIXY_API_HASH -or $env:NAVIXY_API_HASH -eq "YOUR_NAVIXY_API_HASH_HERE") {
    Write-Host "⚠ API key not configured!" -ForegroundColor Red
    Write-Host "Please update: $envScript" -ForegroundColor Yellow
    exit 1
}

# Check Python virtual environment
$venvPython = Join-Path $scriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Write-Host "⚠ Virtual environment not found!" -ForegroundColor Yellow
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to create virtual environment" -ForegroundColor Red
        exit 1
    }
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    & $venvPython -m pip install --upgrade pip
    $requirementsFile = Join-Path $scriptRoot "requirements.txt"
    if (Test-Path $requirementsFile) {
        & $venvPython -m pip install -r $requirementsFile
    } else {
        & $venvPython -m pip install flask requests
    }
}

# Start server
Write-Host ""
Write-Host "Starting API server..." -ForegroundColor Green
Write-Host "Server will run on: http://localhost:$($env:PORT)" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

& $venvPython "$scriptRoot\server.py"
