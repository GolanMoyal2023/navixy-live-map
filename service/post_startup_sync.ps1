# Post-Startup Sync Script
# Runs after services start to sync tunnel URL and open dashboard
# This can be added to Windows Task Scheduler to run at logon

$ErrorActionPreference = "Continue"
$root = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }
$root = $root.TrimEnd("\")

# Setup logging
$logDir = "$root\service\logs"
$logFile = "$logDir\post_startup.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $logFile
}

Write-Log "=== Post-Startup Sync Started ==="

# Wait for services to fully start
Write-Log "Waiting 30 seconds for services to initialize..."
Start-Sleep -Seconds 30

# Check if tunnel service is running
$tunnelService = Get-Service -Name "NavixyQuickTunnel" -ErrorAction SilentlyContinue
if (-not $tunnelService -or $tunnelService.Status -ne "Running") {
    Write-Log "Tunnel service not running, starting it..."
    Start-Service -Name "NavixyQuickTunnel" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 15
}

# Wait for tunnel URL to appear in logs
Write-Log "Looking for tunnel URL in logs..."
$maxWait = 60
$waitCount = 0
$newUrl = $null

while ($waitCount -lt $maxWait -and -not $newUrl) {
    $stderrLog = "$root\service\logs\quick_tunnel_stderr.log"
    if (Test-Path $stderrLog) {
        $logContent = Get-Content $stderrLog -Tail 100 -ErrorAction SilentlyContinue
        foreach ($line in $logContent) {
            if ($line -match 'https://([a-z0-9-]+\.trycloudflare\.com)') {
                $newUrl = "https://$($Matches[1])"
                break
            }
        }
    }
    if (-not $newUrl) {
        Start-Sleep -Seconds 2
        $waitCount += 2
    }
}

if ($newUrl) {
    Write-Log "Found tunnel URL: $newUrl"
    
    # Read current URL
    $urlFile = "$root\.quick_tunnel_url.txt"
    $currentUrl = ""
    if (Test-Path $urlFile) {
        $currentUrl = [System.IO.File]::ReadAllText($urlFile).Trim() -replace '/data$', ''
    }
    
    # Check if URL changed
    if ($newUrl -ne $currentUrl) {
        Write-Log "URL changed! Syncing to GitHub..."
        
        "$newUrl/data" | Out-File -FilePath $urlFile -Encoding UTF8 -NoNewline
        Write-Log "Updated .quick_tunnel_url.txt"
        
        $apiUrlFile = "$root\api-url.json"
        $json = @{ dataUrl = "$newUrl/data" } | ConvertTo-Json -Compress
        Set-Content -Path $apiUrlFile -Value $json -Encoding UTF8 -NoNewline
        Write-Log "Updated api-url.json"
        
        Set-Location $root
        git add api-url.json 2>&1 | Out-Null
        git commit -m "Auto-sync tunnel URL on startup: $newUrl" 2>&1 | Out-Null
        $pushResult = git push 2>&1
        Write-Log "Git push result: $pushResult"
        
        Write-Log "✅ URL synced to GitHub!"
    } else {
        Write-Log "URL unchanged, no sync needed"
    }
} else {
    Write-Log "❌ Could not find tunnel URL in logs"
}

# Open dashboard in browser
Write-Log "Opening dashboard..."
Start-Process "http://localhost:8766"

Write-Log "=== Post-Startup Sync Complete ==="
