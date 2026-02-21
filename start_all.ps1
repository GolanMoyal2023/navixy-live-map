<#
.SYNOPSIS
    Navixy Live Map - Start all services
.DESCRIPTION
    1. Teltonika Broker   TCP:15027  HTTP:8768  (BLE beacons + FMC direct)
    2. Navixy Server               HTTP:8767  (motorized GSE from Navixy cloud)
    3. ngrok HTTP tunnel  8768 -> public HTTPS  (so GitHub Pages map can reach broker)
    4. Updates api-url.json on GitHub if ngrok URL changed
.USAGE
    .\start_all.ps1
    .\start_all.ps1 -Restart   (kill old processes first)
#>
param(
    [switch]$Restart   # Kill existing processes on 8767/8768 before starting
)

$Root      = "D:\New_Recovery\2Plus\navixy-live-map"
$Python    = "$Root\.venv\Scripts\python.exe"
$ApiHash   = "f038d4c96bfc683cdc52337824f7e5f0"

# -------------------------------------------------------
function Write-Step($n, $text) {
    Write-Host ""
    Write-Host "[$n] $text" -ForegroundColor Yellow
}
function Write-OK($text)   { Write-Host "    OK  $text"       -ForegroundColor Green  }
function Write-Skip($text) { Write-Host "    --  $text"       -ForegroundColor Gray   }
function Write-Warn($text) { Write-Host "    !!  $text"       -ForegroundColor Yellow }
function Write-Err($text)  { Write-Host "    XX  $text"       -ForegroundColor Red    }

function Test-PortListening($port) {
    $r = (netstat -ano) | Select-String "0\.0\.0\.0:$port\s.*LISTENING"
    return [bool]$r
}

function Kill-ProcessOnPort($port) {
    $lines = (netstat -ano) | Select-String "0\.0\.0\.0:$port\s.*LISTENING"
    foreach ($line in $lines) {
        if ($line -match '\s+(\d+)$') {
            $pid_ = $Matches[1]
            try { Stop-Process -Id $pid_ -Force -ErrorAction Stop; Write-Skip "Killed PID $pid_ (was on :$port)" }
            catch { Write-Warn "Could not kill PID $pid_" }
        }
    }
}

function Get-NgrokTunnels() {
    try { return (Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -ErrorAction Stop).tunnels }
    catch { return @() }
}

function Add-NgrokHttpTunnel($port, $name) {
    $body = @{ name=$name; proto="http"; addr="$port" } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:4040/api/tunnels" `
             -ContentType "application/json" -Body $body -ErrorAction Stop
        return $r.public_url
    } catch {
        # May already exist - fetch it
        try {
            $r = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels/$name" -ErrorAction Stop
            return $r.public_url
        } catch { return $null }
    }
}

# -------------------------------------------------------
# Git plumbing: push api-url.json to origin/main WITHOUT
# checking out main (avoids locked-file conflicts).
# -------------------------------------------------------
function Push-ApiUrlJson($jsonContent) {
    Push-Location $Root
    try {
        # Refresh origin/main ref
        git fetch origin main --quiet 2>$null

        # Write content to a temp file and hash it as a blob
        $tmp = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($tmp, $jsonContent, [Text.Encoding]::UTF8)
        $blobHash = (git hash-object -w $tmp).Trim()
        Remove-Item $tmp -ErrorAction SilentlyContinue
        if (-not $blobHash) { throw "blob creation failed" }

        # Rebuild the tree from origin/main, replacing api-url.json
        # Use no-BOM UTF8 + cmd redirect to avoid CR corruption on Windows
        $noBom     = New-Object System.Text.UTF8Encoding($false)
        $treeLines = git ls-tree "origin/main" | Where-Object { $_ -notmatch "api-url\.json" }
        $newEntry  = "100644 blob $blobHash`tapi-url.json"
        $treeFile  = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($treeFile, (($treeLines + $newEntry) -join "`n") + "`n", $noBom)
        $newTree   = (cmd /c "git mktree < `"$treeFile`"").Trim()
        Remove-Item $treeFile -ErrorAction SilentlyContinue
        if (-not $newTree) { throw "mktree failed" }

        # Commit on top of origin/main
        $parent  = (git rev-parse "origin/main").Trim()
        $msg     = "Auto-sync broker URL $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        $msgFile = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($msgFile, $msg, $noBom)
        $newCom  = (cmd /c "git commit-tree $newTree -p $parent -F `"$msgFile`"").Trim()
        Remove-Item $msgFile -ErrorAction SilentlyContinue
        if (-not $newCom) { throw "commit-tree failed" }

        # Push
        $out = git push origin "${newCom}:refs/heads/main" 2>&1
        Write-OK "Pushed api-url.json to origin/main ($($newCom.Substring(0,7)))"
        return $true
    } catch {
        Write-Warn "git push failed: $_"
        return $false
    } finally {
        Pop-Location
    }
}

# ================================================================
#  MAIN
# ================================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Navixy Live Map - Starting all services"       -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

if (-not (Test-Path $Python)) {
    Write-Err "Python venv not found: $Python"
    Write-Host "       Run: python -m venv .venv && .\.venv\Scripts\pip install flask requests pyodbc" -ForegroundColor Gray
    exit 1
}

# ---- Optionally kill existing ----
if ($Restart) {
    Write-Step "0" "Stopping existing processes (-Restart)"
    Kill-ProcessOnPort 8767
    Kill-ProcessOnPort 8768
    Start-Sleep -Seconds 2
}

# ================================================================
# STEP 1 - BROKER (port 8768, TCP 15027)
# ================================================================
Write-Step "1/4" "Teltonika Broker  (HTTP :8768  TCP :15027)"

if (Test-PortListening 8768) {
    Write-Skip "already listening on :8768"
} else {
    $cmd = "title Teltonika-Broker && `"$Python`" `"$Root\teltonika_broker.py`""
    Start-Process "cmd.exe" -ArgumentList "/k", $cmd -WorkingDirectory $Root -WindowStyle Normal
    Start-Sleep -Seconds 5

    if (Test-PortListening 8768) { Write-OK "started on :8768" }
    else { Write-Warn "port :8768 not yet listening - may still be starting" }
}

# ================================================================
# STEP 2 - NAVIXY SERVER (port 8767)
# ================================================================
Write-Step "2/4" "Navixy Server     (HTTP :8767)"

if (Test-PortListening 8767) {
    Write-Skip "already listening on :8767"
} else {
    $cmd = "title Navixy-Server && set PORT=8767 && set NAVIXY_API_HASH=$ApiHash && `"$Python`" `"$Root\server.py`""
    Start-Process "cmd.exe" -ArgumentList "/k", $cmd -WorkingDirectory $Root -WindowStyle Normal
    Start-Sleep -Seconds 4

    if (Test-PortListening 8767) { Write-OK "started on :8767" }
    else { Write-Warn "port :8767 not yet listening - may still be starting" }
}

# ================================================================
# STEP 3 - NGROK HTTP TUNNEL (broker :8768)
# ================================================================
Write-Step "3/4" "ngrok HTTP tunnel  (:8768 -> public HTTPS)"

$brokerUrl = $null
$tunnels = Get-NgrokTunnels

if ($tunnels.Count -eq 0) {
    Write-Err "ngrok is not running (port 4040 not responding)"
    Write-Host "        Start ngrok first:  ngrok tcp 15027  (or run service\start_ngrok.ps1)" -ForegroundColor Gray
} else {
    # Look for existing HTTP tunnel on 8768
    foreach ($t in $tunnels) {
        if ($t.proto -in @("https","http") -and $t.config.addr -match "8768") {
            $brokerUrl = $t.public_url -replace "^http://","https://"
            Write-Skip "tunnel already exists: $brokerUrl"
            break
        }
    }

    if (-not $brokerUrl) {
        Write-Host "    adding tunnel..." -ForegroundColor Gray
        $brokerUrl = Add-NgrokHttpTunnel 8768 "broker_http"
        if ($brokerUrl) {
            $brokerUrl = $brokerUrl -replace "^http://","https://"
            Write-OK "$brokerUrl"
        } else {
            Write-Err "could not create HTTP tunnel (check ngrok plan / quota)"
        }
    }
}

# ================================================================
# STEP 4 - UPDATE api-url.json AND PUSH TO GITHUB
# ================================================================
Write-Step "4/4" "Sync api-url.json to GitHub Pages"

if (-not $brokerUrl) {
    Write-Warn "no broker URL - skipping api-url.json update"
} else {
    $newDataUrl  = "$brokerUrl/data"
    $apiUrlFile  = "$Root\api-url.json"
    $currentUrl  = $null

    if (Test-Path $apiUrlFile) {
        try { $currentUrl = (Get-Content $apiUrlFile -Raw | ConvertFrom-Json).dataUrl } catch {}
    }

    if ($currentUrl -eq $newDataUrl) {
        Write-Skip "api-url.json already has correct URL"
    } else {
        $json = "{`"dataUrl`":`"$newDataUrl`"}"
        Write-Host "    new URL: $newDataUrl" -ForegroundColor Gray

        # Also write locally (for reference)
        Set-Content -Path $apiUrlFile -Value $json -Encoding UTF8 -NoNewline

        # Push to origin/main via git plumbing (no branch checkout needed)
        Push-ApiUrlJson $json | Out-Null
    }
}

# ================================================================
# FINAL STATUS
# ================================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  STATUS" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$checks = @(
    @{ Port=8768; Label="Broker  (:8768)" },
    @{ Port=8767; Label="Navixy  (:8767)" }
)
foreach ($c in $checks) {
    try {
        Invoke-WebRequest "http://127.0.0.1:$($c.Port)/health" -TimeoutSec 3 -UseBasicParsing -EA Stop | Out-Null
        Write-Host "  [OK]  $($c.Label)" -ForegroundColor Green
    } catch {
        Write-Host "  [!!]  $($c.Label)  (still starting?)" -ForegroundColor Yellow
    }
}

if ($brokerUrl) {
    Write-Host "  [OK]  ngrok  $brokerUrl" -ForegroundColor Green
} else {
    Write-Host "  [!!]  ngrok  (no HTTP tunnel)" -ForegroundColor Red
}

Write-Host ""
Write-Host "  MAP : https://golanmoyal2023.github.io/navixy-live-map/" -ForegroundColor White
Write-Host "        Select [Both] -> Motorized GSE + BLE Beacons"      -ForegroundColor Gray
Write-Host ""
Write-Host "  To force restart:  .\start_all.ps1 -Restart"            -ForegroundColor Gray
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
