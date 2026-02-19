-- ============================================================
-- Complete Beacon Data: Definitions + Positions
-- Database: 2Plus_AssetTracking
-- Run in SSMS or: sqlcmd -S localhost\SQL2025 -d 2Plus_AssetTracking -i seed_beacon_data.sql
--
-- Reference (Symbol | Beacon      | MAC           | Category     | Type        | Lat       | Lng       )
-- ◆ Eybe2plus1  | 7cd9f407f95c | Towed Device  | eye_beacon   | 32.3119616 | 34.9324433
-- ■ Eybe2plus2  | 7cd9f4003536 | Equipment     | eye_beacon   | 32.3094883 | 34.9303666
-- ▲ EyeBe3     | 7cd9f406427b | Equipment     | eye_beacon   | 32.308865  | 34.93079
-- ● EyeBe4     | 7cd9f407a2db | Equipment     | eye_beacon   | 32.3142616 | 34.9349766
-- ★ Eysen2plus | 7cd9f4116ee7 | Safety        | eye_sensor   | 32.310117  | 34.932402
-- ============================================================

USE [2Plus_AssetTracking];
GO

-- Clear existing data and insert fresh
DELETE FROM BLE_Positions;
DELETE FROM BLE_Definitions;
GO

-- Insert BLE Definitions (known beacons with categories)
INSERT INTO BLE_Definitions (mac, name, category, ble_type, serial_number) VALUES
('7cd9f407f95c', 'Eybe2plus1', 'Towed Device', 'eye_beacon', '6204011070'),
('7cd9f4003536', 'Eybe2plus2', 'Equipment', 'eye_beacon', '6204011168'),
('7cd9f406427b', 'EyeBe3', 'Equipment', 'eye_beacon', ''),
('7cd9f407a2db', 'EyeBe4', 'Equipment', 'eye_beacon', ''),
('7cd9f4116ee7', 'Eysen2plus', 'Safety', 'eye_sensor', '6134010143');
GO

-- Insert BLE Positions with last known locations
-- Columns: mac, name, category, ble_type, serial_number, lat, lng, last_update, is_paired
INSERT INTO BLE_Positions (mac, name, category, ble_type, serial_number, lat, lng, last_update, is_paired) VALUES
('7cd9f407f95c', 'Eybe2plus1', 'Towed Device', 'eye_beacon', '6204011070', 32.3119616, 34.9324433, '2026-02-19 14:22:20', 1),
('7cd9f4003536', 'Eybe2plus2', 'Equipment', 'eye_beacon', '6204011168', 32.3094883, 34.9303666, '2026-02-19 15:18:10', 1),
('7cd9f406427b', 'EyeBe3', 'Equipment', 'eye_beacon', '', 32.308865, 34.93079, '2026-02-19 14:48:23', 1),
('7cd9f407a2db', 'EyeBe4', 'Equipment', 'eye_beacon', '', 32.3142616, 34.9349766, '2026-02-19 14:25:19', 1),
('7cd9f4116ee7', 'Eysen2plus', 'Safety', 'eye_sensor', '6134010143', 32.310117, 34.932402, '2026-02-19 19:14:37', 0);
GO

PRINT 'All beacon definitions and positions inserted!';
GO

-- Verify
-- SELECT * FROM BLE_Definitions;
-- SELECT mac, name, category, ble_type, lat, lng FROM BLE_Positions;
