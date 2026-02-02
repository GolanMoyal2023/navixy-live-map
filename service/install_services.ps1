$ErrorActionPreference = "Stop"

$nssm = "C:\Tools\nssm\nssm.exe"
$root = "D:\New_Recovery\2Plus\navixy-live-map"
$serverScript = "$root\service\start_server.ps1"
$tunnelScript = "$root\service\start_tunnel.ps1"

if (-not (Test-Path $nssm)) {
    throw "NSSM not found at $nssm"
}

if (-not (Test-Path $serverScript)) {
    throw "Missing $serverScript"
}

if (-not (Test-Path $tunnelScript)) {
    throw "Missing $tunnelScript"
}

# Remove existing services if they exist
& $nssm stop NavixyApi | Out-Null
& $nssm remove NavixyApi confirm | Out-Null
& $nssm stop NavixyTunnel | Out-Null
& $nssm remove NavixyTunnel confirm | Out-Null

# Install NavixyApi service
& $nssm install NavixyApi "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$serverScript`""
& $nssm set NavixyApi AppDirectory $root

# Install NavixyTunnel service
& $nssm install NavixyTunnel "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$tunnelScript`""
& $nssm set NavixyTunnel AppDirectory $root

# Start services
& $nssm start NavixyApi
& $nssm start NavixyTunnel

Write-Host "Services installed and started: NavixyApi, NavixyTunnel"
