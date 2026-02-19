# Navixy Live Map – Run & Maintenance

Use this document to **start**, **update**, and **maintain** the service. Everything you need is recorded here.

---

## 1. One-command start (run all)

From the project folder:

```powershell
cd D:\2Plus\Services\navixy-live-map
.\start_all.ps1
```

This opens **3 windows**:

| Window        | Role                    | Port(s)   | Stop by        |
|---------------|-------------------------|-----------|----------------|
| Navixy API    | Fetches Navixy cloud → `/data` for map "Navixy" | 8767      | Close window   |
| Teltonika broker | Devices + BLE → `/data` for map "Direct"     | 15027, 8768 | Close window   |
| Map server    | Serves `index.html`     | 8080      | Close window   |

Then it opens the map in the browser: **http://127.0.0.1:8080/index.html**

---

## 2. Ports and URLs (reference)

| Port   | Service          | URL / use |
|--------|------------------|-----------|
| **8080** | Map UI           | http://127.0.0.1:8080/index.html |
| **8767** | Navixy API       | http://127.0.0.1:8767/data (map source "Navixy") |
| **8768** | Broker HTTP API  | http://127.0.0.1:8768/data (map source "Direct") |
| **15027** | Teltonika TCP  | Devices connect here (not a browser URL) |
| 1433   | SQL Server       | Optional; for BLE persistence |

---

## 3. Manual start (per service)

If you prefer to start services one by one (e.g. in separate terminals):

```powershell
cd D:\2Plus\Services\navixy-live-map
.\.venv\Scripts\Activate.ps1
```

**Terminal 1 – Navixy API**

```powershell
$env:PORT = "8767"
python server.py
```

**Terminal 2 – Teltonika broker**

```powershell
python teltonika_broker.py
```

**Terminal 3 – Map server**

```powershell
python -m http.server 8080
```

Then open: http://127.0.0.1:8080/index.html

---

## 4. Environment and config

| Item | Where | Purpose |
|------|--------|---------|
| **NAVIXY_API_HASH** | env var or `server.py` default | Navixy cloud API auth |
| **NAVIXY_BASE_URL** | env var (optional) | Default: `https://api.navixy.com/v2` |
| **NAVIXY_TIMEOUT** | env var (optional) | Default: 10 seconds |
| **PORT** | env var for `server.py` | Navixy API port (default 8080 in code; use 8767 for map) |
| **db_helper.py** | `SQL_SERVER`, `SQL_DATABASE`, `SQL_USER`, `SQL_PASSWORD` | SQL Server for BLE/tracker persistence |

Current DB settings in `db_helper.py`:

- Server: `localhost\SQL2025`
- Database: `2Plus_AssetTracking`
- User: `sa` (set password in code or env if you change it)

---

## 5. Dependencies (Python)

```powershell
cd D:\2Plus\Services\navixy-live-map
.\.venv\Scripts\pip install flask requests pyodbc
```

Or from repo root if you have a requirements file:

```powershell
.\.venv\Scripts\pip install -r requirements.txt
```

---

## 6. Database (optional but recommended)

**First-time setup**

```powershell
cd D:\2Plus\Services\navixy-live-map
.\.venv\Scripts\python.exe setup_database.py
```

**Tables used:** `BLE_Definitions`, `BLE_Positions`, `BLE_Movement_Log`, `Trackers`, `BLE_Pairing_History`, `System_Config`.

**Seed beacon data (definitions + positions):** To load the 5 beacons (Eybe2plus1, Eybe2plus2, EyeBe3, EyeBe4, Eysen2plus) with categories and last-known positions, run:

```powershell
sqlcmd -S localhost\SQL2025 -d 2Plus_AssetTracking -i "D:\2Plus\Services\navixy-live-map\scripts\seed_beacon_data.sql"
```

Or open `scripts/seed_beacon_data.sql` in SSMS and execute. This replaces all rows in `BLE_Definitions` and `BLE_Positions`.

---

## 7. Key files (what to touch when updating)

| File | Role |
|------|------|
| **index.html** | Map UI; data source URLs (Navixy 8767, Direct 8768); default source (Navixy/Direct). |
| **server.py** | Navixy API proxy; `/data` for map "Navixy"; optional DB. |
| **teltonika_broker.py** | TCP 15027 + HTTP 8768; BLE logic; optional DB. |
| **db_helper.py** | SQL connection and BLE/tracker read/write. |
| **setup_database.py** | Creates/updates DB schema. |
| **start_all.ps1** | Starts all services; adjust if you add/remove processes or ports. |
| **send_test_avl.py** | Injects one test tracker + BLE for local demo. |

---

## 8. Updating the service (code/config)

1. **Pull or copy** new code into `D:\2Plus\Services\navixy-live-map`.
2. **Restart** the processes that use changed code:
   - Navixy only → close and restart the **Navixy API** window.
   - Broker only → close and restart the **Teltonika broker** window.
   - Map only → refresh browser; if you changed static files, restart the **Map server** window (port 8080).
3. **DB schema** changes → run again:
   ```powershell
   .\.venv\Scripts\python.exe setup_database.py
   ```
4. **Dependency** changes → reinstall then restart:
   ```powershell
   .\.venv\Scripts\pip install -r requirements.txt
   ```

---

## 9. Keeping it running (restart / recover)

- **All services:** run `.\start_all.ps1` again (close old windows if still open).
- **Single service:** close its window and start only that command from section 3.
- **After reboot:** run `.\start_all.ps1` (or the manual commands in section 3). No Windows Service is installed by default; add one if you need auto-start (see `service\` scripts).
- **Failure / maintenance recovery:** run `.\service\recovery.ps1` (see section 14).

---

## 10. Quick health check

```powershell
# Navixy data (should return JSON with rows)
Invoke-RestMethod "http://127.0.0.1:8767/data" | Select-Object success, @{N='rows';E={$_.rows.Count}}

# Broker (should return service name + counts)
Invoke-RestMethod "http://127.0.0.1:8768/" | ConvertTo-Json

# Map (should open in browser)
Start-Process "http://127.0.0.1:8080/index.html"
```

---

## 11. Troubleshooting

| Symptom | Check |
|--------|--------|
| Map shows "Failed to load live data" | Ensure **Navixy** window is running (8767) or **Direct** (8768). In map, click the correct **Data:** source (Navixy / Direct). |
| No BLE on map | Use **Data: Direct**; broker must be running. Optionally call `POST http://127.0.0.1:8768/ble/set-position` with `{"mac":"...","lat":...,"lng":...}` to pin a beacon. |
| Beacon in wrong location | Correct it: `POST http://127.0.0.1:8768/ble/set-position` with correct `lat`/`lng`. Example (PowerShell): `Invoke-RestMethod -Uri "http://127.0.0.1:8768/ble/set-position" -Method POST -ContentType "application/json" -Body '{"mac":"7cd9f407f95c","lat":32.123,"lng":34.456}'`. Replace MAC/lat/lng as needed. |
| DB not used (db_enabled: false) | Install pyodbc; run `setup_database.py`; fix `db_helper.py` connection (server, database, user, password). |
| Port in use | Change PORT (Navixy) or ports in `teltonika_broker.py` (15027, 8768) or use another port for `http.server 8080`. |
| Navixy API hash invalid | Set env **NAVIXY_API_HASH** or update default in `server.py`. |

---

## 12. Summary checklist for “up and running”

- [ ] Python 3 + venv in `D:\2Plus\Services\navixy-live-map`
- [ ] `pip install flask requests pyodbc`
- [ ] (Optional) SQL Server `localhost\SQL2025`, DB `2Plus_AssetTracking`, run `setup_database.py`
- [ ] Run `.\start_all.ps1` (or start Navixy, broker, map server manually)
- [ ] Open http://127.0.0.1:8080/index.html
- [ ] Use **Navixy** for cloud assets (5032, 6074, etc.); **Direct** for broker + BLE

---

## 13. Deploy to GitHub Pages (for clients)

To publish the map so clients can use **https://golanmoyal2023.github.io/navixy-live-map/**:

1. **Production API (config.js)**  
   The live map uses `config.js`. The tunnel at **navixy-livemap.moyals.net** forwards to **localhost:8765** only, so `config.js` sets `NAVIXY_MAP_DATA_SOURCES` to the same `/data` URL for both sources. If you expose 8767 and 8768 separately, you can set `NAVIXY_MAP_API_BASE` instead (map will use `:8767/data` and `:8768/data`).

2. **Sync and push** (from repo root):
   ```powershell
   cd D:\2Plus\Services\navixy-live-map
   .\service\deploy_to_github.ps1
   ```
   This adds `index.html`, `config.js`, `llbg_layers.geojson`, and `Pictures/`, commits, and pushes to `origin`. GitHub Pages serves from the default branch.

3. **After push**  
   Changes appear at https://golanmoyal2023.github.io/navixy-live-map/ in a few minutes; use a hard refresh (Ctrl+Shift+R) if needed.

For server/tunnel setup, see **SERVER_DEPLOYMENT_GUIDE.md** and **SETUP_GUIDE.md**.

---

## 14. Local configuration and recovery (service setup)

**Local config (already in use):** The map uses **config.js** with `NAVIXY_MAP_API_BASE = "http://127.0.0.1"` so the map always talks to this machine (ports 8767 and 8768). Optional Windows services (from `service\`) can run the API, tunnel, dashboard, and URL-sync; see `service\install_services_with_dashboard.ps1` and `service\start_url_sync.ps1` if you use tunnel + GitHub URL sync.

**Recovery script (maintenance / down / failure):**

When the server is down, after maintenance, or to force a clean restart:

```powershell
cd D:\2Plus\Services\navixy-live-map
.\service\recovery.ps1
```

| Option | Effect |
|--------|--------|
| (none) | Health-check 8767, 8768, 8080; if any fail, restart Windows services (if installed), then free ports and run `start_all.ps1` in a new window. |
| `-VerifyOnly` | Only run health check and report; do not restart anything. |
| `-RestartServicesOnly` | Only restart Windows services (NavixyApi, NavixyQuickTunnel, NavixyDashboard, NavixyUrlSync) if present; do not run `start_all.ps1`. |

Logs: `service\logs\recovery.log`. After recovery, the script opens the map in the browser if all endpoints are OK.
