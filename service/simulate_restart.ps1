# Simulate Restart - Tests all 4 services as if computer rebooted
# Run as Administrator

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SIMULATING SYSTEM RESTART" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Run as Administrator!" -ForegroundColor Red
    exit 1
}

$services = @("NavixyUrlSync", "NavixyDashboard", "NavixyQuickTunnel", "NavixyApi")
$root = "D:\New_Recovery\2Plus\navixy-live-map"

# Clear old tunnel logs to simulate fresh start
Write-Host "Step 1: Clearing tunnel logs (simulate fresh boot)..." -ForegroundColor Yellow
$logFile = "$root\service\logs\quick_tunnel_stderr.log"
if (Test-Path $logFile) {
    Clear-Content $logFile -ErrorAction SilentlyContinue
    Write-Host "  Tunnel logs cleared" -ForegroundColor Gray
}

# Clear URL sync log
$urlSyncLog = "$root\service\logs\url_sync.log"
if (Test-Path $urlSyncLog) {
    # Keep last 50 lines for reference
    $content = Get-Content $urlSyncLog -Tail 50 -ErrorAction SilentlyContinue
    $content | Set-Content $urlSyncLog -ErrorAction SilentlyContinue
    Write-Host "  URL sync log trimmed" -ForegroundColor Gray
}

# Stop all services (reverse order)
Write-Host ""
Write-Host "Step 2: Stopping all services..." -ForegroundColor Yellow
foreach ($svc in $services) {
    Write-Host "  Stopping $svc..." -ForegroundColor Gray -NoNewline
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Write-Host " Stopped" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 3: Waiting 3 seconds (simulate boot delay)..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Start services in boot order
Write-Host ""
Write-Host "Step 4: Starting services (boot sequence)..." -ForegroundColor Yellow

$bootOrder = @("NavixyApi", "NavixyQuickTunnel", "NavixyDashboard", "NavixyUrlSync")

foreach ($svc in $bootOrder) {
    Write-Host "  Starting $svc..." -ForegroundColor Gray -NoNewline
    Start-Service -Name $svc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $status = (Get-Service -Name $svc -ErrorAction SilentlyContinue).Status
    if ($status -eq "Running") {
        Write-Host " Running" -ForegroundColor Green
    } else {
        Write-Host " $status" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RESTART SIMULATION COMPLETE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "All services restarted. Now monitoring URL sync..." -ForegroundColor Yellow
Write-Host ""
Write-Host "The URL sync service will:" -ForegroundColor Gray
Write-Host "  1. Wait 45 seconds for tunnel to stabilize" -ForegroundColor Gray
Write-Host "  2. Detect the new tunnel URL" -ForegroundColor Gray
Write-Host "  3. Update index.html and push to GitHub" -ForegroundColor Gray
Write-Host ""
Write-Host "Monitoring URL sync log (Ctrl+C to stop)..." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Monitor the URL sync log
$lastLines = 0
$timeout = 120  # 2 minutes max
$startTime = Get-Date

while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
    if (Test-Path $urlSyncLog) {
        $content = Get-Content $urlSyncLog -ErrorAction SilentlyContinue
        $newLines = $content.Count
        
        if ($newLines -gt $lastLines) {
            $content[$lastLines..($newLines-1)] | ForEach-Object {
                if ($_ -match "URL CHANGE DETECTED") {
                    Write-Host $_ -ForegroundColor Yellow
                } elseif ($_ -match "SUCCESS|Sync complete") {
                    Write-Host $_ -ForegroundColor Green
                } elseif ($_ -match "ERROR|fatal") {
                    Write-Host $_ -ForegroundColor Red
                } else {
                    Write-Host $_ -ForegroundColor Gray
                }
            }
            $lastLines = $newLines
        }
        
        # Check if sync completed
        if ($content -match "Sync complete") {
            Write-Host ""
            Write-Host "============================================" -ForegroundColor Green
            Write-Host "  URL SYNC COMPLETED!" -ForegroundColor Green
            Write-Host "============================================" -ForegroundColor Green
            break
        }
    }
    
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Final service status:" -ForegroundColor Cyan
Get-Service -Name "NavixyApi","NavixyQuickTunnel","NavixyDashboard","NavixyUrlSync" | Format-Table Name, Status -AutoSize

Write-Host ""
Write-Host "Current tunnel URL:" -ForegroundColor Cyan
Get-Content "$root\.quick_tunnel_url.txt"

Write-Host ""
Write-Host "Check dashboard: http://localhost:8766" -ForegroundColor White
Write-Host "Check external:  https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
