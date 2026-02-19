-- View: vw_BLE_Diagnostics (aggregated per beacon)
-- Depends on: BLE_Scans (mac, scan_time, rssi, battery_percent, tracker_imei, is_known_beacon; optional: distance_meters),
--             BLE_Definitions (mac, name, category, ble_type)
-- If BLE_Scans has no distance_meters, add: ALTER TABLE BLE_Scans ADD distance_meters FLOAT NULL;
-- The broker uses this view to fill battery and "Last saw" on the map when live device data is missing.
-- Run in database: [2Plus_AssetTracking]

USE [2Plus_AssetTracking];
GO

CREATE OR ALTER VIEW [dbo].[vw_BLE_Diagnostics] AS
SELECT
    s.mac,
    d.name AS beacon_name,
    d.category,
    d.ble_type,
    COUNT(*) AS total_scans,
    MIN(s.scan_time) AS first_seen,
    MAX(s.scan_time) AS last_seen,
    DATEDIFF(MINUTE, MAX(s.scan_time), GETDATE()) AS minutes_since_last_scan,
    AVG(s.rssi) AS avg_rssi,
    MIN(s.rssi) AS min_rssi,
    MAX(s.rssi) AS max_rssi,
    AVG(s.battery_percent) AS avg_battery,
    MIN(s.battery_percent) AS min_battery,
    MAX(s.battery_percent) AS max_battery,
    COUNT(DISTINCT s.tracker_imei) AS unique_trackers,
    COUNT(DISTINCT CAST(s.scan_time AS DATE)) AS days_active,
    COUNT(DISTINCT DATEPART(HOUR, s.scan_time)) AS unique_hours,
    AVG(s.distance_meters) AS avg_distance_meters,
    CASE
        WHEN MAX(s.scan_time) > DATEADD(MINUTE, -5, GETDATE()) THEN 'Active'
        WHEN MAX(s.scan_time) > DATEADD(HOUR, -1, GETDATE()) THEN 'Recent'
        WHEN MAX(s.scan_time) > DATEADD(DAY, -1, GETDATE()) THEN 'Stale'
        ELSE 'Offline'
    END AS current_status
FROM BLE_Scans s
LEFT JOIN BLE_Definitions d ON s.mac = d.mac
WHERE s.is_known_beacon = 1
GROUP BY s.mac, d.name, d.category, d.ble_type;
GO

PRINT 'View vw_BLE_Diagnostics created successfully!';
GO

-- Verify & test
-- SELECT name FROM sys.views WHERE name = 'vw_BLE_Diagnostics';
-- SELECT * FROM [dbo].[vw_BLE_Diagnostics];
-- SELECT beacon_name, avg_battery, current_status FROM vw_BLE_Diagnostics WHERE avg_battery < 20;
-- SELECT beacon_name, last_seen, minutes_since_last_scan FROM vw_BLE_Diagnostics WHERE current_status = 'Offline';
