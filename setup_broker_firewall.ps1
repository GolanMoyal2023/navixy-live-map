#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets up firewall rules for Teltonika Direct Broker
.DESCRIPTION
    Creates inbound firewall rule for TCP port 15027
    Must be run as Administrator
#>

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Teltonika Broker Firewall Setup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Must run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as Administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n[1/3] Creating firewall rule for TCP 15027..." -ForegroundColor Yellow

# Remove existing rule if any
$existingRule = Get-NetFirewallRule -DisplayName "Teltonika Broker TCP 15027" -ErrorAction SilentlyContinue
if ($existingRule) {
    Remove-NetFirewallRule -DisplayName "Teltonika Broker TCP 15027"
    Write-Host "  Removed existing rule" -ForegroundColor Gray
}

# Create new rule
New-NetFirewallRule `
    -DisplayName "Teltonika Broker TCP 15027" `
    -Description "Allow Teltonika FMC650/FMC003 devices to connect to local broker" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 15027 `
    -Action Allow `
    -Profile Any `
    -Enabled True | Out-Null

Write-Host "  [OK] Firewall rule created!" -ForegroundColor Green

Write-Host "`n[2/3] Verifying port is listening..." -ForegroundColor Yellow
$listening = netstat -ano | Select-String ":15027.*LISTEN"
if ($listening) {
    Write-Host "  [OK] Port 15027 is listening" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Port 15027 not listening - start teltonika_broker.py" -ForegroundColor Yellow
}

Write-Host "`n[3/3] Getting your IP address..." -ForegroundColor Yellow
$wifiIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*WiFi*" -and $_.IPAddress -notlike "169.*" }).IPAddress
$ethIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" -and $_.IPAddress -notlike "169.*" }).IPAddress

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  SETUP COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configure your Teltonika FMC650:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  GPRS -> Second Server Settings:" -ForegroundColor White
Write-Host "    Server Mode:  Duplicate" -ForegroundColor White
if ($wifiIP) {
    Write-Host "    Domain:       $wifiIP" -ForegroundColor Yellow
}
if ($ethIP) {
    Write-Host "    Domain (alt): $ethIP" -ForegroundColor Gray
}
Write-Host "    Port:         15027" -ForegroundColor Yellow
Write-Host "    Protocol:     TCP" -ForegroundColor White
Write-Host ""
Write-Host "After configuring, Save and Reboot the device." -ForegroundColor Cyan
Write-Host ""
