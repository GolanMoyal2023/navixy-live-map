# Cloudflare Tunnel Setup for Navixy Live Map

**Priority:** Must work for public access to map API  
**Tunnel type:** Named tunnel (not quick tunnel)

---

## Requirements

### 1. Core infrastructure

| Item | Detail |
|------|--------|
| **Named tunnel** | ID `e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab`, name `navixy-live` |
| **Config (user)** | `C:\Users\GolanMoyal\.cloudflared\config.yml` (after `cloudflared tunnel login`) |
| **Config (service)** | Copied to repo `.cloudflared\` so NavixyTunnel can read it |
| **Windows service** | `NavixyTunnel` – runs `service\start_tunnel.ps1` |
| **API server** | `NavixyApi` on port **8765** – tunnel forwards to `http://127.0.0.1:8765` |
| **Public URL** | `https://navixy-livemap.moyals.net/data` (DNS at registrar) |

### 2. Success criteria

- Tunnel connects: logs show "Registered tunnel connection".
- Multiple connections (e.g. tlv01, fra13, fra21) in Cloudflare dashboard.
- Service auto-starts on reboot and runs without manual intervention.
- `https://navixy-livemap.moyals.net/data` is reachable from the internet (after DNS is set).

---

## Fix: Service cannot access config (permission issue)

The service runs as a different account and cannot read `C:\Users\GolanMoyal\.cloudflared\`.

**Solution:** Copy config and credentials into the repo so the service can read them.

### Option A – One-step script (recommended)

1. Run as the user who has Cloudflare config (e.g. GolanMoyal):
   ```powershell
   cd D:\2Plus\Services\navixy-live-map\service
   .\fix_and_start_cloudflare_tunnel.ps1
   ```
2. If it says “Run as Administrator”, open PowerShell as Admin and run the same script again. It will restart the service and verify.

### Option B – Manual steps

1. **Copy config to repo** (run as user who has the config):
   ```powershell
   cd D:\2Plus\Services\navixy-live-map\service
   .\fix_tunnel_permissions.ps1
   ```
   This copies:
   - `config.yml` → `<repo>\.cloudflared\config.yml`
   - `e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.json` → `<repo>\.cloudflared\`
   and fixes credentials path inside the copied config.

2. **Restart the service** (run as Administrator):
   ```powershell
   Restart-Service -Name NavixyTunnel -Force
   ```
   Or:
   ```powershell
   .\restart_tunnel.ps1
   ```

### Why this works

- `start_tunnel.ps1` looks for config in this order:
  1. `<repo>\.cloudflared\config.yml` ← **used by service** (AppDirectory = repo root)
  2. `%USERPROFILE%\.cloudflared\config.yml`
  3. Fallbacks for specific username
- After the fix, the service finds the config in the repo and no longer needs access to your user profile.

---

## Verification

### Pre-fix

- [ ] `Get-Service NavixyTunnel` – status
- [ ] `Get-Content service\logs\navixy_tunnel.log -Tail 30` – look for "Configuration file ... empty" or "Access is denied"
- [ ] Config exists: `Test-Path C:\Users\GolanMoyal\.cloudflared\config.yml`

### Post-fix

- [ ] `Get-Service NavixyTunnel` = Running
- [ ] `Get-Process cloudflared` = process running
- [ ] Logs: "Registered tunnel connection" in `service\logs\navixy_tunnel.log`
- [ ] Cloudflare Zero Trust dashboard: tunnel `navixy-live` shows as UP
- [ ] Local API: `Invoke-RestMethod -Uri "http://127.0.0.1:8765/data"` returns JSON

### After DNS is configured

- [ ] `nslookup navixy-livemap.moyals.net` resolves
- [ ] `https://navixy-livemap.moyals.net/data` returns JSON from external network
- [ ] GitHub Pages map can load data when opened from mobile/external

---

## DNS (manual, at registrar)

1. In Cloudflare Zero Trust: get the CNAME target for your tunnel (e.g. `e42dd40c-8c96-4a5c-911e-66bbd9b3f1ab.cfargotunnel.com`).
2. At the domain registrar for `moyals.net`, add a CNAME:
   - Name: `navixy-livemap` (or the subdomain you use)
   - Target: `<tunnel-id>.cfargotunnel.com`
3. Wait for propagation (up to 24–48 hours).

---

## Component status

| Component | Required | Blocking if missing |
|-----------|----------|---------------------|
| Cloudflare config (user) | Yes | Run `cloudflared tunnel login` and create tunnel |
| Config in repo `.cloudflared\` | Yes | Run `fix_tunnel_permissions.ps1` |
| NavixyTunnel service | Yes | Install via `install_services.ps1` or `install_services_with_dashboard.ps1` |
| NavixyApi (8765) | Yes | Must be running for tunnel to serve /data |
| DNS for navixy-livemap.moyals.net | Yes for public URL | Configure at registrar |

---

## Scripts reference

| Script | Purpose |
|--------|---------|
| `service\fix_tunnel_permissions.ps1` | Copy user’s .cloudflared config + credentials to repo `.cloudflared\` |
| `service\fix_and_start_cloudflare_tunnel.ps1` | Fix permissions + restart NavixyTunnel (run as user, then as Admin if needed) |
| `service\restart_tunnel.ps1` | Restart NavixyTunnel (Admin), show status and recent logs |
| `service\start_tunnel.ps1` | What the service runs: start cloudflared with config from repo first |

---

**Next steps:** Fix permissions → Restart service → Verify logs and dashboard → Configure DNS for public URL.
