# Verify System After Restart
# Run this script after computer restart to verify everything works

$ErrorActionPreference = "Continue"
$repoRoot = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }
$repoRoot = $repoRoot.TrimEnd("\")

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🔄 Post-Restart Verification Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Date: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

$results = @()
$allPassed = $true

# Test 1: Check Windows Services
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Test 1: Windows Services" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

$services = @("NavixyApi", "NavixyBroker", "NavixyTunnel", "NavixyQuickTunnel", "NavixyDashboard")
foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Host "  ✅ $svc - Running" -ForegroundColor Green
        $results += @{Name = $svc; Status = "PASS"; Details = "Running" }
    } else {
        Write-Host "  ❌ $svc - NOT Running" -ForegroundColor Red
        $results += @{Name = $svc; Status = "FAIL"; Details = "Not running or not found" }
        $allPassed = $false
    }
}
Write-Host ""

# Test 2: Local API
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Test 2: Local API (http://localhost:8767)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

try {
    $localApi = Invoke-WebRequest -Uri "http://localhost:8767/data" -UseBasicParsing -TimeoutSec 15
    if ($localApi.StatusCode -eq 200) {
        $data = $localApi.Content | ConvertFrom-Json
        $trackerCount = $data.rows.Count
        Write-Host "  ✅ Local API - Working (Status: 200, Trackers: $trackerCount)" -ForegroundColor Green
        $results += @{Name = "Local API"; Status = "PASS"; Details = "Status 200, $trackerCount trackers" }
    } else {
        Write-Host "  ❌ Local API - Bad status: $($localApi.StatusCode)" -ForegroundColor Red
        $results += @{Name = "Local API"; Status = "FAIL"; Details = "Status $($localApi.StatusCode)" }
        $allPassed = $false
    }
} catch {
    Write-Host "  ❌ Local API - Error: $($_.Exception.Message)" -ForegroundColor Red
    $results += @{Name = "Local API"; Status = "FAIL"; Details = $_.Exception.Message }
    $allPassed = $false
}
Write-Host ""

# Test 3: Dashboard
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Test 3: Dashboard (http://localhost:8766)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

try {
    $dashboard = Invoke-WebRequest -Uri "http://localhost:8766/api/status" -UseBasicParsing -TimeoutSec 10
    if ($dashboard.StatusCode -eq 200) {
        $status = $dashboard.Content | ConvertFrom-Json
        $healthPct = $status.health_percentage
        Write-Host "  ✅ Dashboard - Working (Health: $healthPct%)" -ForegroundColor Green
        $results += @{Name = "Dashboard"; Status = "PASS"; Details = "Health: $healthPct%" }
    } else {
        Write-Host "  ❌ Dashboard - Bad status: $($dashboard.StatusCode)" -ForegroundColor Red
        $results += @{Name = "Dashboard"; Status = "FAIL"; Details = "Status $($dashboard.StatusCode)" }
        $allPassed = $false
    }
} catch {
    Write-Host "  ❌ Dashboard - Error: $($_.Exception.Message)" -ForegroundColor Red
    $results += @{Name = "Dashboard"; Status = "FAIL"; Details = $_.Exception.Message }
    $allPassed = $false
}
Write-Host ""

# Test 4: Tunnel URL
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Test 4: Cloudflare Tunnel URL" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

$tunnelUrlFile = Join-Path $repoRoot ".quick_tunnel_url.txt"
if (Test-Path $tunnelUrlFile) {
    $tunnelUrl = [System.IO.File]::ReadAllText($tunnelUrlFile).Trim()
    Write-Host "  Tunnel URL: $tunnelUrl" -ForegroundColor Gray
    
    try {
        $tunnel = Invoke-WebRequest -Uri $tunnelUrl -UseBasicParsing -TimeoutSec 15
        if ($tunnel.StatusCode -eq 200) {
            Write-Host "  ✅ Tunnel URL - Working (Status: 200)" -ForegroundColor Green
            $results += @{Name = "Tunnel URL"; Status = "PASS"; Details = "Status 200" }
        } else {
            Write-Host "  ❌ Tunnel URL - Bad status: $($tunnel.StatusCode)" -ForegroundColor Red
            $results += @{Name = "Tunnel URL"; Status = "FAIL"; Details = "Status $($tunnel.StatusCode)" }
            $allPassed = $false
        }
    } catch {
        Write-Host "  ❌ Tunnel URL - Error: $($_.Exception.Message)" -ForegroundColor Red
        $results += @{Name = "Tunnel URL"; Status = "FAIL"; Details = $_.Exception.Message }
        $allPassed = $false
    }
} else {
    Write-Host "  ❌ Tunnel URL file not found" -ForegroundColor Red
    $results += @{Name = "Tunnel URL"; Status = "FAIL"; Details = "File not found" }
    $allPassed = $false
}
Write-Host ""

# Test 5: GitHub Pages
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Test 5: GitHub Pages" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

try {
    $github = Invoke-WebRequest -Uri "https://golanmoyal2023.github.io/navixy-live-map/" -UseBasicParsing -TimeoutSec 15
    if ($github.StatusCode -eq 200) {
        Write-Host "  ✅ GitHub Pages - Accessible (Status: 200)" -ForegroundColor Green
        $results += @{Name = "GitHub Pages"; Status = "PASS"; Details = "Status 200" }
    } else {
        Write-Host "  ❌ GitHub Pages - Bad status: $($github.StatusCode)" -ForegroundColor Red
        $results += @{Name = "GitHub Pages"; Status = "FAIL"; Details = "Status $($github.StatusCode)" }
        $allPassed = $false
    }
} catch {
    Write-Host "  ❌ GitHub Pages - Error: $($_.Exception.Message)" -ForegroundColor Red
    $results += @{Name = "GitHub Pages"; Status = "FAIL"; Details = $_.Exception.Message }
    $allPassed = $false
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "🎉 ALL TESTS PASSED!" -ForegroundColor Green
} else {
    Write-Host "⚠️  SOME TESTS FAILED" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Results Table
Write-Host "Results Summary:" -ForegroundColor Yellow
Write-Host "┌──────────────────────┬────────┬─────────────────────────────────┐"
Write-Host "│ Test                 │ Status │ Details                         │"
Write-Host "├──────────────────────┼────────┼─────────────────────────────────┤"
foreach ($r in $results) {
    $name = $r.Name.PadRight(20)
    $status = if ($r.Status -eq "PASS") { "✅ PASS" } else { "❌ FAIL" }
    $details = $r.Details
    if ($details.Length -gt 31) { $details = $details.Substring(0, 28) + "..." }
    $details = $details.PadRight(31)
    Write-Host "│ $name │ $status │ $details │"
}
Write-Host "└──────────────────────┴────────┴─────────────────────────────────┘"
Write-Host ""

# Open URLs for visual verification
if ($allPassed) {
    Write-Host "Opening URLs for visual verification..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:8766"  # Dashboard
    Start-Sleep -Seconds 1
    Start-Process "https://golanmoyal2023.github.io/navixy-live-map/"  # External Map
    Start-Sleep -Seconds 1
    Start-Process $tunnelUrl  # Tunnel API
    Write-Host ""
    Write-Host "✅ Opened 3 URLs for visual verification:" -ForegroundColor Green
    Write-Host "  1. Dashboard (localhost:8766)" -ForegroundColor White
    Write-Host "  2. External Map (GitHub Pages)" -ForegroundColor White
    Write-Host "  3. Tunnel API" -ForegroundColor White
}

Write-Host ""
Write-Host "Test completed at $(Get-Date)" -ForegroundColor Gray
Write-Host ""
