# Start Tunnel with Auto URL Sync
# This script starts the tunnel and automatically syncs URL changes to GitHub

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot

# Setup logging
$logDir = "$root\service\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = "$logDir\tunnel_sync.log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $logFile
    Write-Host "$timestamp - $Message"
}

Write-Log "=== Tunnel with Auto-Sync Started ==="
Write-Log "Root directory: $root"

# Path to URL file
$urlFile = "$root\.quick_tunnel_url.txt"
$indexFile = "$root\index.html"

# Start cloudflared in background and capture output
$tunnelProcess = $null
$lastUrl = ""

# Read current URL if exists
if (Test-Path $urlFile) {
    $lastUrl = [System.IO.File]::ReadAllText($urlFile).Trim() -replace '/data$', ''
    Write-Log "Previous URL: $lastUrl"
}

# Create a temporary file to capture tunnel output
$tempOutput = "$logDir\tunnel_output_temp.txt"
if (Test-Path $tempOutput) { Remove-Item $tempOutput -Force }

Write-Log "Starting cloudflared quick tunnel..."

# Start cloudflared and redirect output
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cloudflared"
$psi.Arguments = "tunnel --url http://127.0.0.1:8765 --ha-connections 1"
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi

# Event handlers to capture output
$outputBuilder = New-Object System.Text.StringBuilder
$errorBuilder = New-Object System.Text.StringBuilder

$outputHandler = {
    if (-not [String]::IsNullOrEmpty($EventArgs.Data)) {
        $outputBuilder.AppendLine($EventArgs.Data)
    }
}
$errorHandler = {
    if (-not [String]::IsNullOrEmpty($EventArgs.Data)) {
        $errorBuilder.AppendLine($EventArgs.Data)
        # Also write to stderr log
        $EventArgs.Data | Out-File -Append -FilePath "$using:logDir\quick_tunnel_stderr.log"
    }
}

$process.add_OutputDataReceived($outputHandler)
$process.add_ErrorDataReceived($errorHandler)

$process.Start() | Out-Null
$process.BeginOutputReadLine()
$process.BeginErrorReadLine()

Write-Log "Cloudflared started with PID: $($process.Id)"

# Function to sync URL to GitHub
function Sync-UrlToGitHub {
    param($NewUrl)
    
    Write-Log "Syncing new URL to GitHub: $NewUrl"
    
    try {
        # Update .quick_tunnel_url.txt
        "$NewUrl/data" | Out-File -FilePath $urlFile -Encoding UTF8 -NoNewline
        Write-Log "Updated .quick_tunnel_url.txt"
        
        # Update index.html
        $indexContent = Get-Content $indexFile -Raw
        $pattern = 'const LIVE_API_URL = "https://[^"]+/data"'
        $replacement = "const LIVE_API_URL = `"$NewUrl/data`""
        $newContent = $indexContent -replace $pattern, $replacement
        $newContent | Set-Content $indexFile -NoNewline
        Write-Log "Updated index.html"
        
        # Push to GitHub
        Set-Location $root
        git add index.html 2>&1 | Out-Null
        $commitResult = git commit -m "Auto-sync tunnel URL: $NewUrl" 2>&1
        Write-Log "Git commit: $commitResult"
        
        $pushResult = git push 2>&1
        Write-Log "Git push: $pushResult"
        
        Write-Log "✅ URL synced to GitHub successfully!"
        return $true
    } catch {
        Write-Log "❌ Error syncing URL: $($_.Exception.Message)"
        return $false
    }
}

# Monitor for URL changes
$urlFound = $false
$checkCount = 0
$maxChecks = 60  # Check for 60 seconds

Write-Log "Monitoring for tunnel URL..."

while (-not $process.HasExited) {
    Start-Sleep -Seconds 2
    $checkCount++
    
    # Check stderr log for URL
    $stderrLog = "$logDir\quick_tunnel_stderr.log"
    if (Test-Path $stderrLog) {
        $logContent = Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue
        if ($logContent -match 'https://([a-z0-9-]+\.trycloudflare\.com)') {
            $newUrl = "https://$($Matches[1])"
            
            if ($newUrl -ne $lastUrl) {
                Write-Log "New tunnel URL detected: $newUrl"
                
                if (Sync-UrlToGitHub -NewUrl $newUrl) {
                    $lastUrl = $newUrl
                    $urlFound = $true
                }
            } elseif (-not $urlFound) {
                Write-Log "URL unchanged: $newUrl"
                $urlFound = $true
            }
        }
    }
    
    # Only log periodically
    if ($checkCount % 30 -eq 0) {
        Write-Log "Tunnel still running... (PID: $($process.Id))"
    }
}

Write-Log "Cloudflared process exited with code: $($process.ExitCode)"
