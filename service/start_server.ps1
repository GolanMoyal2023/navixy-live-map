$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\\env.ps1"

Set-Location $root

$python = Join-Path $root ".venv\\Scripts\\python.exe"
if (-not (Test-Path $python)) {
    throw "Python venv not found: $python"
}

& $python "$root\\server.py"
