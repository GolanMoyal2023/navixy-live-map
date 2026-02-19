# Navixy Services - Quick Troubleshooting Guide

> **Issue:** Some services installed but remain **Paused** or **Stopped**

---

## 🚨 Quick Fix: Start Services in Order

Services have **dependencies** - they must start in a specific order:

```powershell
# Run as Administrator!

# Step 1: Start API first (no dependencies)
Start-Service NavixyApi
Start-Sleep -Seconds 5

# Step 2: Verify API is running
if ((Get-Service NavixyApi).Status -eq "Running") {
    Write-Host "✅ NavixyApi Running" -ForegroundColor Green
    
    # Step 3: Start Tunnel (depends on API)
    Start-Service NavixyQuickTunnel
    Start-Sleep -Seconds 5
    
    # Step 4: Start Dashboard (depends on API)
    Start-Service NavixyDashboard
    
    # Step 5: Start URL Sync (depends on Tunnel)
    Start-Service NavixyUrlSync
} else {
    Write-Host "❌ NavixyApi Failed - check logs!" -ForegroundColor Red
}

# Check final status
Get-Service Navixy* | Format-Table Name, Status
```

---

## 📊 Service Dependency Chain

```
NavixyApi (MUST start first)
    │
    ├──▶ NavixyQuickTunnel (needs API)
    │         │
    │         └──▶ NavixyUrlSync (needs Tunnel)
    │
    └──▶ NavixyDashboard (needs API)
```

**If NavixyApi fails → ALL other services will fail/pause!**

---

## 🔍 Common Issues & Fixes

### Issue 1: NavixyApi Won't Start

**Check 1:** Is `NAVIXY_API_HASH` set?
```powershell
# Open and verify
notepad "D:\path\to\navixy-live-map\service\env.ps1"

# Should contain:
# $env:NAVIXY_API_HASH = "your_hash_here"
```

**Check 2:** Is Python venv working?
```powershell
& "D:\path\to\navixy-live-map\.venv\Scripts\python.exe" --version
```

**Check 3:** View error log
```powershell
Get-Content "D:\path\to\navixy-live-map\service\logs\navixyapi_stderr.log" -Tail 30
```

---

### Issue 2: NavixyQuickTunnel Won't Start

**Check 1:** Is cloudflared installed?
```powershell
cloudflared --version
```

**Check 2:** Is port 8765 accessible?
```powershell
Test-NetConnection -ComputerName localhost -Port 8765
```

**Check 3:** Kill existing cloudflared processes
```powershell
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
```

---

### Issue 3: NavixyDashboard Won't Start

**Check 1:** Is port 8766 free?
```powershell
netstat -ano | findstr ":8766"
```

**Check 2:** Test manually
```powershell
cd "D:\path\to\navixy-live-map"
.\.venv\Scripts\python.exe dashboard.py
```

---

### Issue 4: NavixyUrlSync Won't Start

**Check 1:** Is Git installed?
```powershell
git --version
```

**Check 2:** Is the repo initialized?
```powershell
cd "D:\path\to\navixy-live-map"
git status
```

---

## 🔧 Reset All Services (Nuclear Option)

If nothing works, completely reinstall:

```powershell
# Run as Administrator!
$nssm = "C:\ProgramData\chocolatey\bin\nssm.exe"

# Remove all services
"NavixyApi","NavixyQuickTunnel","NavixyDashboard","NavixyUrlSync" | ForEach-Object {
    & $nssm stop $_ 2>$null
    & $nssm remove $_ confirm 2>$null
}

# Reinstall
cd "D:\path\to\navixy-live-map\REMOTE_SERVER_INSTALL"
.\install_all_services.ps1 -InstallPath "D:\path\to\navixy-live-map"
```

---

## ✅ Verify Everything Works

```powershell
# 1. All services running?
Get-Service Navixy* | Where-Object Status -ne "Running"
# (Should return nothing if all running)

# 2. API responding?
Invoke-RestMethod http://localhost:8765/health

# 3. Dashboard accessible?
Start-Process http://localhost:8766

# 4. Tunnel URL exists?
Get-Content "D:\path\to\navixy-live-map\.quick_tunnel_url.txt"
```

---

## 📝 Path Reminder

**Update all paths above with YOUR actual installation path!**

| Computer | Typical Path |
|----------|--------------|
| Main Station | `D:\New_Recovery\2Plus\navixy-live-map` |
| Other Server | `D:\Sharing Resorce\Services\navixy-live-map` |

---

*Quick reference for service troubleshooting - 2026-02-03*
