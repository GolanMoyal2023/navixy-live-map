# URL Sync Service - v2
# Monitors cloudflared quick tunnel URL via local REST API and syncs to api-url.json on GitHub
# Runs as a Windows service - NO human intervention needed

$ErrorActionPreference = "Continue"
$root    = "D:\New_Recovery\2Plus\navixy-live-map"
$newRoot = "D:\New_Recovery\2Plus\navixy-live-map-main-live"

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
Write-Log "URL Sync Service v2 Started"
Write-Log "Monitoring cloudflared REST API for quick tunnel URL"
Write-Log "Updating: $newRoot\api-url.json"
Write-Log "=========================================="

$lastSyncedUrl  = ""
$apiUrlFile     = "$newRoot\api-url.json"
$checkInterval  = 30   # seconds between URL checks

# Read last known URL
if (Test-Path $apiUrlFile) {
    try {
        $existing = Get-Content $apiUrlFile -Raw | ConvertFrom-Json
        $lastSyncedUrl = ($existing.dataUrl -replace '/data$', '')
        Write-Log "Last known URL from api-url.json: $lastSyncedUrl"
    } catch {
        Write-Log "Could not parse existing api-url.json"
    }
}

function Get-CurrentTunnelUrl {
    # Method 1: cloudflared local metrics REST API (most reliable)
    $ports = @(20243, 20241, 20242, 2000)
    foreach ($port in $ports) {
        try {
            $r = Invoke-RestMethod "http://127.0.0.1:$port/quicktunnel" -TimeoutSec 3
            if ($r.hostname) {
                return "https://$($r.hostname)"
            }
        } catch {}
    }

    # Method 2: Scan stderr log for trycloudflare URL
    $logPaths = @(
        "$root\service\logs\quick_tunnel_stderr.log",
        "C:\Temp\cf_clean.log"
    )
    foreach ($lp in $logPaths) {
        if (Test-Path $lp) {
            try {
                $content = [System.IO.File]::ReadAllBytes($lp)
                # Handle both UTF-8 and UTF-16 (service logs use UTF-16)
                $text = [System.Text.Encoding]::Unicode.GetString($content)
                if ($text -notmatch 'trycloudflare\.com') {
                    $text = [System.Text.Encoding]::UTF8.GetString($content)
                }
                $matches = [regex]::Matches($text, 'https://[a-z0-9-]+\.trycloudflare\.com')
                if ($matches.Count -gt 0) {
                    return $matches[$matches.Count - 1].Value
                }
            } catch {}
        }
    }

    return $null
}

function Sync-UrlToGitHub {
    param([string]$NewUrl)

    Write-Log "Syncing URL to GitHub: $NewUrl"

    try {
        # 1. Update api-url.json
        $jsonContent = "{`"dataUrl`":`"$NewUrl/data`"}"
        $noBomUtf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($apiUrlFile, $jsonContent, $noBomUtf8)
        Write-Log "Updated api-url.json: $jsonContent"

        # 2. Git commit + push
        Set-Location $newRoot
        git config --global --add safe.directory $newRoot 2>&1 | Out-Null
        git config user.email "navixy-urlsync@localhost" 2>&1 | Out-Null
        git config user.name "Navixy URL Sync" 2>&1 | Out-Null

        git add api-url.json 2>&1 | Out-Null
        $commitOut = git commit -m "auto: sync tunnel URL $NewUrl" 2>&1
        Write-Log "git commit: $commitOut"

        $pushOut = git push origin HEAD:main 2>&1
        Write-Log "git push: $pushOut"

        Write-Log "SUCCESS: URL synced to GitHub."
        return $true
    } catch {
        Write-Log "ERROR syncing URL: $($_.Exception.Message)"
        return $false
    }
}

# Wait for cloudflared to start
Write-Log "Waiting 20 seconds for tunnel services to initialize..."
Start-Sleep -Seconds 20

Write-Log "Starting URL monitoring loop (every $checkInterval sec)..."

while ($true) {
    try {
        $currentUrl = Get-CurrentTunnelUrl

        if ($currentUrl) {
            if ($currentUrl -ne $lastSyncedUrl) {
                Write-Log "URL CHANGE: '$lastSyncedUrl' -> '$currentUrl'"

                # Brief wait to confirm tunnel is stable
                Start-Sleep -Seconds 5

                # Verify the URL responds
                try {
                    $test = Invoke-RestMethod "$currentUrl/health" -TimeoutSec 10
                    if ($test.status -eq "ok") {
                        Write-Log "URL verified working: $currentUrl/health -> ok"
                        if (Sync-UrlToGitHub -NewUrl $currentUrl) {
                            $lastSyncedUrl = $currentUrl
                            Write-Log "Sync complete. Live map should update within ~60 seconds."
                        }
                    } else {
                        Write-Log "URL health check returned unexpected: $($test|ConvertTo-Json -Compress)"
                    }
                } catch {
                    Write-Log "URL not reachable yet ($($_.Exception.Message)), will retry..."
                }
            }
            # else: URL unchanged, nothing to do
        } else {
            Write-Log "No active tunnel URL found, waiting..."
        }
    } catch {
        Write-Log "Error in monitoring loop: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $checkInterval
}
