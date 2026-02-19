# Start Teltonika broker (TCP 15027, HTTP 8768) - same logic as start_all.ps1 / branch
# Used by NavixyBroker Windows service so broker runs from repo (branch) code.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$python = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    throw "Python venv not found: $python"
}

& $python "$root\teltonika_broker.py"
