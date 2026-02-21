# Beacon Data Reference (Dev Station)

Complete beacon definitions and positions for **2Plus_AssetTracking**. Use `seed_beacon_data.sql` to load this data.

---

## Run the seed script

**SSMS:** Open `seed_beacon_data.sql` and execute.

**Command line:**
```powershell
sqlcmd -S localhost\SQL2025 -d 2Plus_AssetTracking -i "D:\2Plus\Services\navixy-live-map\scripts\seed_beacon_data.sql"
```

---

## Reference table

| Symbol | Beacon     | MAC           | Category     | Type        | Lat        | Lng        | SN        |
|--------|------------|---------------|--------------|-------------|------------|------------|-----------|
| ◆      | Eybe2plus1 | 7cd9f407f95c  | Towed Device | eye_beacon  | 32.3119616 | 34.9324433 | 6204011070 |
| ■      | Eybe2plus2 | 7cd9f4003536  | Equipment    | eye_beacon  | 32.3094883 | 34.9303666 | 6204011168 |
| ▲      | EyeBe3     | 7cd9f406427b  | Equipment    | eye_beacon  | 32.308865  | 34.93079   | –         |
| ●      | EyeBe4     | 7cd9f407a2db  | Equipment    | eye_beacon  | 32.3142616 | 34.9349766 | –         |
| ★      | Eysen2plus | 7cd9f4116ee7  | Safety       | eye_sensor  | 32.310117  | 34.932402  | 6134010143 |

---

## Category legend

| Category     | Symbol | Color  | Description                          |
|-------------|--------|--------|--------------------------------------|
| Towed Device| ◆      | Purple | Assets that get towed (GPU, stairs)  |
| Equipment   | ■ ▲ ●  | Blue   | General ground equipment             |
| Safety      | ★      | Orange | Safety-critical equipment            |

---

## Verify after insert

```sql
-- Check definitions
SELECT * FROM BLE_Definitions;

-- Check positions
SELECT mac, name, category, ble_type, lat, lng FROM BLE_Positions;
```

---

*Data source: dev station. Same content as `seed_beacon_data.sql`.*
