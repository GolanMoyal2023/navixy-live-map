# Post-Startup Sync Script
# Runs 1 minute after logon (via NavixyPostStartupSync scheduled task)
# Ensures ngrok HTTP tunnel is active and api-url.json is current on GitHub Pages

$ErrorActionPreference = "Continue"
$root = "D:\New_Recovery\2Plus\navixy-live-map"

$logDir  = "$root\service\logs"
$logFile = "$logDir\post_startup.log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $msg" | Out-File -Append -FilePath $logFile
}

Write-Log "=== Post-Startup Sync Started ==="

# ----------------------------------------------------------------
# STEP 1 - Wait for ngrok REST API to be available (up to 60s)
# ----------------------------------------------------------------
Write-Log "Waiting for ngrok REST API on :4040..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels" -ErrorAction Stop | Out-Null
        $ready = $true; break
    } catch { Start-Sleep -Seconds 2 }
}
if (-not $ready) { Write-Log "ngrok not available after 60s - aborting"; exit 1 }
Write-Log "ngrok REST API ready"

# ----------------------------------------------------------------
# STEP 2 - Ensure HTTP tunnel for broker :8768 exists
# ----------------------------------------------------------------
$tunnelName = "broker-http"
$brokerUrl  = $null

try {
    $existing  = Invoke-RestMethod "http://127.0.0.1:4040/api/tunnels/$tunnelName" -ErrorAction Stop
    $brokerUrl = $existing.public_url
    Write-Log "HTTP tunnel already exists: $brokerUrl"
} catch {
    Write-Log "Adding HTTP tunnel for :8768..."
    try {
        $body     = '{"name":"' + $tunnelName + '","proto":"http","addr":"8768"}'
        $r        = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:4040/api/tunnels" `
                        -ContentType "application/json" -Body $body -ErrorAction Stop
        $brokerUrl = $r.public_url
        Write-Log "HTTP tunnel created: $brokerUrl"
    } catch {
        Write-Log "Failed to create HTTP tunnel: $_"
    }
}

if (-not $brokerUrl) { Write-Log "No broker URL - skipping api-url.json sync"; exit 1 }

# ----------------------------------------------------------------
# STEP 3 - Update api-url.json locally + push to GitHub Pages
#          Git plumbing (no checkout) avoids locked log-file conflicts
# ----------------------------------------------------------------
$newDataUrl = "$brokerUrl/data"
$apiUrlFile = "$root\api-url.json"
$noBom      = New-Object System.Text.UTF8Encoding($false)

$currentUrl = ""
if (Test-Path $apiUrlFile) {
    try { $currentUrl = ([IO.File]::ReadAllText($apiUrlFile, $noBom) | ConvertFrom-Json).dataUrl } catch {}
}

if ($currentUrl -eq $newDataUrl) {
    Write-Log "api-url.json already correct: $newDataUrl"
} else {
    Write-Log "Updating api-url.json: $newDataUrl"
    $json = "{`"dataUrl`":`"$newDataUrl`"}"
    [IO.File]::WriteAllText($apiUrlFile, $json, $noBom)

    Push-Location $root
    try {
        git fetch origin main --quiet 2>$null

        $tmp = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($tmp, $json, $noBom)
        $blobHash = (git hash-object -w $tmp).Trim()
        Remove-Item $tmp -ErrorAction SilentlyContinue

        $treeLines = (git ls-tree "origin/main") | Where-Object { $_ -notmatch "api-url" }
        $newEntry  = "100644 blob $blobHash`tapi-url.json"
        $treeFile  = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($treeFile, (($treeLines + $newEntry) -join "`n") + "`n", $noBom)
        $newTree = (cmd /c "git mktree < `"$treeFile`"").Trim()
        Remove-Item $treeFile -ErrorAction SilentlyContinue

        if ($newTree) {
            $parent  = (git rev-parse "origin/main").Trim()
            $msgFile = [IO.Path]::GetTempFileName()
            [IO.File]::WriteAllText($msgFile, "Auto-sync broker URL $(Get-Date -Format 'yyyy-MM-dd HH:mm')", $noBom)
            $newCom  = (cmd /c "git commit-tree $newTree -p $parent -F `"$msgFile`"").Trim()
            Remove-Item $msgFile -ErrorAction SilentlyContinue
            if ($newCom) {
                git push origin "${newCom}:refs/heads/main" 2>&1 | Out-Null
                Write-Log "Pushed api-url.json ($($newCom.Substring(0,7)))"
            } else { Write-Log "commit-tree failed" }
        } else { Write-Log "mktree failed" }
    } catch { Write-Log "Git push error: $_" }
    finally  { Pop-Location }
}

Write-Log "=== Post-Startup Sync Complete ==="
