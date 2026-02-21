# Get Cloudflare Quick Tunnel URL
$ErrorActionPreference = "Continue"

Write-Host "Starting Cloudflare quick tunnel..." -ForegroundColor Cyan
Write-Host "Please wait for the URL..." -ForegroundColor Yellow
Write-Host ""

# Start tunnel and capture output
$process = Start-Process -FilePath "cloudflared" -ArgumentList "tunnel", "--url", "http://127.0.0.1:8765" -NoNewWindow -PassThru -RedirectStandardOutput "tunnel_stdout.txt" -RedirectStandardError "tunnel_stderr.txt"

Start-Sleep -Seconds 12

# Read output files
$stdout = Get-Content "tunnel_stdout.txt" -ErrorAction SilentlyContinue
$stderr = Get-Content "tunnel_stderr.txt" -ErrorAction SilentlyContinue

$tunnelUrl = $null

# Look for URL in both outputs
$allOutput = @()
if ($stdout) { $allOutput += $stdout }
if ($stderr) { $allOutput += $stderr }

foreach ($line in $allOutput) {
    if ($line -match 'https://([a-z0-9-]+)\.trycloudflare\.com') {
        $tunnelUrl = $matches[0]
        break
    }
    # Also check for URL in different format
    if ($line -match 'trycloudflare\.com') {
        $tunnelUrl = $line -replace '.*(https://[^\s]+trycloudflare\.com).*', '$1'
        if ($tunnelUrl -match 'https://') {
            break
        }
    }
}

if ($tunnelUrl) {
    Write-Host "Tunnel URL found: $tunnelUrl" -ForegroundColor Green
    Write-Host ""
    Write-Host "Keep this process running!" -ForegroundColor Yellow
    Write-Host "Process ID: $($process.Id)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To stop: Stop-Process -Id $($process.Id)" -ForegroundColor Gray
    
    # Save URL to file
    Set-Content -Path ".tunnel_url.txt" -Value $tunnelUrl
    
    return $tunnelUrl
} else {
    Write-Host "Could not extract URL automatically" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Output:" -ForegroundColor Cyan
    if ($stdout) { Write-Host $stdout }
    if ($stderr) { Write-Host $stderr }
    Write-Host ""
    Write-Host "Please check the output above for the tunnel URL" -ForegroundColor Yellow
    Write-Host "Or run manually: cloudflared tunnel --url http://127.0.0.1:8765" -ForegroundColor White
    
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    return $null
}
