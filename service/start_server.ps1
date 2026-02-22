$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\\env.ps1"

# Map requires server.py on :8767 (env.ps1 defaults to 8765 - override here)
$env:PORT = "8767"

Set-Location $root

$python = Join-Path $root ".venv\\Scripts\\python.exe"
if (-not (Test-Path $python)) {
    throw "Python venv not found: $python"
}

& $python "$root\\server.py"
