# BLE data in SQL – what the broker needs

Using your local SQL data as the **start point** until new data arrives from the broker (Teltonika device).  
The broker reads from these tables and serves them on `/data`; when live data appears, it overwrites in memory for that MAC.

---

## 1. Table: **BLE_Positions**

This is the main table. The broker uses it to fill the map (position, battery, last saw).

| Column               | Type           | Required | Description |
|----------------------|----------------|----------|-------------|
| **mac**              | VARCHAR(20)    | Yes      | Beacon MAC, lowercase (e.g. `7cd9f407f95c`). Must be UNIQUE. |
| **lat**              | FLOAT          | Yes*     | Latitude. *Required for the beacon to show on the map.* |
| **lng**              | FLOAT          | Yes*     | Longitude. |
| **last_update**      | DATETIME       | No       | When the beacon was last seen → becomes **"Last saw"** in the popup. |
| **battery_percent**  | INT            | No       | Battery 0–100 (or volts × 100 if you store volts). → **Battery** in popup. |
| **last_tracker_id**  | INT or VARCHAR | No       | Tracker/vehicle ID that last reported this beacon. |
| **last_tracker_label**| VARCHAR(100)   | No       | Tracker name (e.g. "SKODA") → **"Last set by"** in popup. |
| **is_paired**        | BIT (0/1)      | No       | 0 or 1. Default 0. |
| **pairing_start**    | DATETIME       | No       | When current pairing started. |
| **pairing_duration_sec** | INT        | No       | Seconds paired. Default 0. |
| **magnet_status**    | VARCHAR(20)    | No       | Optional magnet sensor value. |
| **name**             | VARCHAR(100)   | No       | Display name (e.g. "Eybe2plus1"). |
| **category**         | VARCHAR(50)    | No       | e.g. "Towed Device", "Equipment". |
| **ble_type**         | VARCHAR(50)    | No       | e.g. "eye_beacon". Default "eye_beacon". |
| **serial_number**    | VARCHAR(50)    | No       | S/N shown in popup. |

Minimum to see something on the map: **mac**, **lat**, **lng**.  
For **Battery** and **Last saw**: also **battery_percent** and **last_update**.

---

## 2. Table: **BLE_Definitions** (optional)

Used for display name, category, type. If you only fill **BLE_Positions** (with name, category, ble_type, serial_number), the broker still works.  
If you use BLE_Definitions, the broker merges name/category/type from here for known MACs.

| Column         | Type        | Required | Description |
|----------------|-------------|----------|-------------|
| **mac**        | VARCHAR(20) | Yes      | Same as in BLE_Positions, UNIQUE. |
| **name**       | VARCHAR(100)| Yes      | Display name. |
| **category**   | VARCHAR(50) | No       | e.g. "Towed Device". |
| **ble_type**   | VARCHAR(50) | No       | e.g. "eye_beacon". |
| **serial_number** | VARCHAR(50) | No    | S/N. |
| **asset_id**   | VARCHAR(50) | No       | Your asset ID. |
| **notes**      | TEXT        | No       | Free text. |

---

## 3. What to export from your SQL

From your existing system, export one row per beacon with at least:

- **mac** (e.g. `7cd9f407f95c`)
- **lat**, **lng**
- **last_update** (date/time last seen)
- **battery_percent** (0–100, or your battery value)
- **last_tracker_label** (e.g. "Direct" or vehicle name)
- **name**, **category** (optional but recommended)

Same names or map them to the columns above when importing.

---

## 4. Example INSERT (BLE_Positions)

```sql
INSERT INTO BLE_Positions (mac, lat, lng, last_update, battery_percent, last_tracker_label, name, category, ble_type, serial_number)
VALUES 
  ('7cd9f407f95c', 32.311962, 34.932443, '2026-02-19 14:25:19', 85, 'Direct', 'Eybe2plus1', 'Towed Device', 'eye_beacon', '6204011070'),
  ('7cd9f407a2db', 32.314262, 34.934977, '2026-02-19 14:25:19', NULL, 'Unknown', 'EyeBe4', 'Equipment', 'eye_beacon', NULL);
```

---

## 5. Flow

1. You **export** from your SQL (MAC + lat, lng, last_update, battery, name, etc.).
2. You **import** into **BLE_Positions** (and optionally **BLE_Definitions**) in the broker DB (`2Plus_AssetTracking`).
3. You **restart the broker**. It loads these rows into memory and serves them on `/data`.
4. The **map** shows them (position, battery, Last saw) until the Teltonika device sends new data for that MAC; then the broker overwrites with live data.

Database and connection are configured in **`db_helper.py`** (server, database, user, password).

---

## 6. View: **vw_BLE_Diagnostics** (optional – your 2Plus DB)

If your database has **`[2Plus_AssetTracking].[dbo].[vw_BLE_Diagnostics]`** (e.g. from another 2Plus app), the broker will use it to fill **battery** and **Last saw** when live device data is missing.

- The broker calls **`get_all_ble_from_diagnostics_view()`** and takes the **latest row per MAC** (by `scan_time`).
- It maps: `battery_percent` → Battery, `scan_time` → Last saw, `lat`/`lng`/`name`/`category`/`tracker_imei` as needed.
- We do **not** create this view in our repo; it must exist in your DB. If it’s missing, the broker skips it and uses only `BLE_Positions` / in-memory data.
