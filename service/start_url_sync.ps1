# URL Sync Service
# Monitors tunnel logs and automatically syncs URL changes to GitHub
# Runs as a Windows service - NO human intervention needed
# Tunnel: NavixyQuickTunnel writes URL to quick_tunnel_stderr.log; this service updates api-url.json and pushes.

$ErrorActionPreference = "Continue"
$root = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }
$root = $root.TrimEnd("\")

# Setup logging
$logDir = "$root\service\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = "$logDir\url_sync.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $logFile
}

Write-Log "=========================================="
Write-Log "URL Sync Service Started (root: $root)"
Write-Log "=========================================="

$urlFile = "$root\.quick_tunnel_url.txt"
$apiUrlFile = "$root\api-url.json"
$stderrLog = "$root\service\logs\quick_tunnel_stderr.log"
$lastSyncedUrl = ""

# Read last synced URL
if (Test-Path $urlFile) {
    $lastSyncedUrl = [System.IO.File]::ReadAllText($urlFile).Trim() -replace '/data$', ''
    Write-Log "Last synced URL: $lastSyncedUrl"
}

function Get-TunnelUrlFromLogs {
    if (-not (Test-Path $stderrLog)) { return $null }
    
    $logContent = Get-Content $stderrLog -Tail 200 -ErrorAction SilentlyContinue
    $foundUrl = $null
    
    foreach ($line in $logContent) {
        if ($line -match 'https://([a-z0-9-]+\.trycloudflare\.com)') {
            $foundUrl = "https://$($Matches[1])"
        }
    }
    
    return $foundUrl
}

function Sync-UrlToGitHub {
    param($NewUrl)
    
    Write-Log "Syncing URL to GitHub: $NewUrl"
    
    try {
        # Update .quick_tunnel_url.txt (used by dashboard and local refs)
        "$NewUrl/data" | Out-File -FilePath $urlFile -Encoding UTF8 -NoNewline
        Write-Log "Updated .quick_tunnel_url.txt"
        
        # Update api-url.json (map on GitHub Pages reads this for mobile/external)
        $dataUrl = "$NewUrl/data"
        $json = @{ dataUrl = $dataUrl } | ConvertTo-Json -Compress
        Set-Content -Path $apiUrlFile -Value $json -Encoding UTF8 -NoNewline
        Write-Log "Updated api-url.json"
        
        Set-Location $root
        $rootEscaped = $root -replace '\\', '/'
        git config --global --add safe.directory $root 2>&1 | Out-Null
        git config --global --add safe.directory $rootEscaped 2>&1 | Out-Null
        git config user.email "navixy-service@localhost" 2>&1 | Out-Null
        git config user.name "Navixy URL Sync Service" 2>&1 | Out-Null
        Write-Log "Git configured (safe.directory + identity)"
        
        git add api-url.json 2>&1 | Out-Null
        $commitResult = git commit -m "Auto-sync tunnel URL (service): $NewUrl" 2>&1
        Write-Log "Git commit: $commitResult"
        
        $pushResult = git push 2>&1
        Write-Log "Git push: $pushResult"
        
        Write-Log "SUCCESS: URL synced to GitHub!"
        return $true
    } catch {
        Write-Log "ERROR syncing URL: $($_.Exception.Message)"
        return $false
    }
}

# Initial wait for tunnel service to start
Write-Log "Waiting 45 seconds for tunnel service to initialize..."
Start-Sleep -Seconds 45

# Main monitoring loop
$checkInterval = 30  # Check every 30 seconds
$syncAttempted = $false

Write-Log "Starting URL monitoring loop (checking every $checkInterval seconds)..."

while ($true) {
    try {
        $currentUrl = Get-TunnelUrlFromLogs
        
        if ($currentUrl) {
            if ($currentUrl -ne $lastSyncedUrl) {
                Write-Log "URL CHANGE DETECTED!"
                Write-Log "  Old: $lastSyncedUrl"
                Write-Log "  New: $currentUrl"
                
                # Wait a few seconds to ensure tunnel is stable
                Start-Sleep -Seconds 5
                
                # Verify URL is actually working
                try {
                    $testResponse = Invoke-WebRequest -Uri "$currentUrl/data" -UseBasicParsing -TimeoutSec 10
                    if ($testResponse.StatusCode -eq 200) {
                        Write-Log "URL verified working (Status 200)"
                        
                        if (Sync-UrlToGitHub -NewUrl $currentUrl) {
                            $lastSyncedUrl = $currentUrl
                            $syncAttempted = $true
                            Write-Log "Sync complete. External access should work in ~30 seconds."
                        }
                    } else {
                        Write-Log "URL returned status $($testResponse.StatusCode), skipping sync"
                    }
                } catch {
                    Write-Log "URL not yet reachable: $($_.Exception.Message)"
                }
            } elseif (-not $syncAttempted) {
                # First run, URL unchanged but verify it's synced
                Write-Log "URL unchanged: $currentUrl"
                $syncAttempted = $true
            }
        } else {
            Write-Log "No tunnel URL found in logs yet..."
        }
    } catch {
        Write-Log "Error in monitoring loop: $($_.Exception.Message)"
    }
    
    Start-Sleep -Seconds $checkInterval
}
