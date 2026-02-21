# Start Dashboard Service
# Runs the dashboard Flask app using the project venv

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\env.ps1"

Set-Location $root

# Use the same venv as the API server
$python = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    # Fallback to system python
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $python) {
        throw "Python not found"
    }
}

$dashboardScript = Join-Path $root "dashboard.py"

Write-Host "Starting Dashboard Service..." -ForegroundColor Cyan
Write-Host "Python: $python" -ForegroundColor Gray
Write-Host "Dashboard: http://127.0.0.1:8766" -ForegroundColor Yellow

# Run dashboard
& $python $dashboardScript
