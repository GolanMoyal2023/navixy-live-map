"""
SQL Server Database Helper for BLE Position Tracking
Provides functions to store and retrieve BLE positions from SQL Server
"""

import pyodbc
from datetime import datetime
from typing import Dict, List, Any, Optional

# SQL Server connection settings
SQL_SERVER = r"localhost\SQL2025"
SQL_DATABASE = "2Plus_AssetTracking"
SQL_USER = "sa"
SQL_PASSWORD = "P@ssword0"

# Connection pool (simple)
_connection = None

def get_connection():
    """Get SQL Server connection (with simple pooling)"""
    global _connection
    try:
        if _connection is not None:
            # Test if connection is still valid
            cursor = _connection.cursor()
            cursor.execute("SELECT 1")
            cursor.close()
            return _connection
    except:
        _connection = None
    
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE={SQL_DATABASE};"
        f"UID={SQL_USER};"
        f"PWD={SQL_PASSWORD};"
        f"TrustServerCertificate=yes;"
    )
    _connection = pyodbc.connect(conn_str, autocommit=False)
    print(f"[DB] Connected to {SQL_DATABASE}")
    return _connection


def get_ble_definitions() -> Dict[str, Dict[str, Any]]:
    """Get all known BLE definitions from database"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT mac, name, category, ble_type, serial_number, asset_id, notes
            FROM BLE_Definitions
        """)
        
        definitions = {}
        for row in cursor.fetchall():
            mac = row[0].lower() if row[0] else ""
            definitions[mac] = {
                "name": row[1],
                "category": row[2],
                "type": row[3],
                "sn": row[4],
                "asset_id": row[5],
                "notes": row[6],
            }
        return definitions
    except Exception as e:
        print(f"[DB ERROR] get_ble_definitions: {e}")
        return {}


def get_ble_position(mac: str) -> Optional[Dict[str, Any]]:
    """Get current position of a BLE by MAC address"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT lat, lng, last_tracker_id, last_tracker_label, last_update,
                   is_paired, pairing_start, pairing_duration_sec, battery_percent, magnet_status
            FROM BLE_Positions
            WHERE mac = ?
        """, mac.lower())
        
        row = cursor.fetchone()
        if row:
            return {
                "lat": row[0],
                "lng": row[1],
                "last_tracker_id": row[2],
                "last_tracker_label": row[3],
                "last_update": row[4].isoformat() if row[4] else None,
                "is_paired": bool(row[5]),
                "pairing_start": row[6].isoformat() if row[6] else None,
                "pairing_duration_sec": row[7],
                "battery_percent": row[8],
                "magnet_status": row[9],
            }
        return None
    except Exception as e:
        print(f"[DB ERROR] get_ble_position: {e}")
        return None


def get_all_ble_from_diagnostics_view() -> Dict[str, Dict[str, Any]]:
    """
    Get aggregated BLE state per MAC from vw_BLE_Diagnostics (if it exists in 2Plus_AssetTracking).
    View has one row per beacon: beacon_name, category, ble_type, last_seen, avg_battery, etc.
    Use this to feed battery and "Last saw" to the map when broker has no live data.
    Returns same shape as get_all_ble_positions (lat/lng will be None; broker merges with BLE_Positions).
    """
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT mac, beacon_name, category, ble_type, last_seen, avg_battery
            FROM [dbo].[vw_BLE_Diagnostics]
        """)
        positions = {}
        for row in cursor.fetchall():
            mac = (row[0] or "").lower().replace(":", "").replace("-", "")
            if not mac:
                continue
            last_seen = row[4]
            positions[mac] = {
                "lat": None,
                "lng": None,
                "last_tracker_id": None,
                "last_tracker_label": None,
                "last_update": last_seen.isoformat() if last_seen else None,
                "is_paired": False,
                "pairing_start": None,
                "pairing_duration_sec": 0,
                "battery_percent": int(row[5]) if row[5] is not None else None,
                "magnet_status": None,
                "name": row[1],
                "category": row[2],
                "type": row[3] if row[3] else "eye_beacon",
                "sn": "",
            }
        return positions
    except Exception as e:
        print(f"[DB] vw_BLE_Diagnostics not available: {e}")
        return {}


def get_all_ble_positions() -> Dict[str, Dict[str, Any]]:
    """Get all BLE positions from database"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT mac, lat, lng, last_tracker_id, last_tracker_label,
                   last_update, is_paired, pairing_start, pairing_duration_sec,
                   battery_percent, magnet_status, name, category, ble_type, serial_number,
                   rssi, contact_type, last_seen, temperature, humidity, battery_voltage
            FROM BLE_Positions
        """)

        positions = {}
        for row in cursor.fetchall():
            mac = row[0].lower() if row[0] else ""
            positions[mac] = {
                "lat":               float(row[1]) if row[1] is not None else None,
                "lng":               float(row[2]) if row[2] is not None else None,
                "last_tracker_id":   str(row[3]) if row[3] else None,
                "last_tracker_label": row[4],
                "last_update":       row[5].isoformat() if row[5] else None,
                "is_paired":         bool(row[6]) if row[6] is not None else False,
                "pairing_start":     row[7].isoformat() if row[7] else None,
                # frontend uses pos.pairing_duration (not pairing_duration_sec)
                "pairing_duration":  row[8],
                # frontend uses pos.battery (not battery_percent)
                "battery":           row[9],
                "magnet_status":     row[10],
                "name":              row[11],
                "category":          row[12],
                "type":              row[13],
                "sn":                row[14],
                "rssi":              float(row[15]) if row[15] is not None else None,
                "contact_type":      row[16],
                # last_seen = Navixy beacon timestamp (when tracker actually saw it)
                # falls back to last_update (DB write time) if not yet populated
                "last_seen":         row[17].isoformat() if row[17] else (row[5].isoformat() if row[5] else None),
                "temperature":       float(row[18]) if row[18] is not None else None,
                "humidity":          float(row[19]) if row[19] is not None else None,
                "battery_voltage":   float(row[20]) if row[20] is not None else None,
            }
        return positions
    except Exception as e:
        print(f"[DB ERROR] get_all_ble_positions: {e}")
        return {}


def update_ble_position(
    mac: str,
    lat: float,
    lng: float,
    tracker_id,  # Can be int or str (IMEI)
    tracker_label: str,
    is_paired: bool = False,
    pairing_start: datetime = None,
    pairing_duration_sec: int = 0,
    battery_percent=None,
    magnet_status: str = None,
    log_movement: bool = False,
    old_lat: float = None,
    old_lng: float = None,
    rssi: float = None,
    contact_type: str = None,
    last_seen_navixy: str = None,
) -> bool:
    """Update or insert BLE position"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        mac = mac.lower()

        # Parse last_seen_navixy string → datetime for DB storage
        last_seen_dt = None
        if last_seen_navixy:
            try:
                last_seen_dt = datetime.strptime(str(last_seen_navixy)[:19], "%Y-%m-%d %H:%M:%S")
            except Exception:
                pass

        # Check if position exists
        cursor.execute("SELECT id, lat, lng FROM BLE_Positions WHERE mac = ?", mac)
        existing = cursor.fetchone()

        if existing:
            # Update existing position
            cursor.execute("""
                UPDATE BLE_Positions
                SET lat = ?, lng = ?, last_tracker_id = ?, last_tracker_label = ?,
                    last_update = GETDATE(), is_paired = ?, pairing_start = ?,
                    pairing_duration_sec = ?,
                    battery_percent = COALESCE(?, battery_percent),
                    magnet_status = COALESCE(?, magnet_status),
                    rssi = COALESCE(?, rssi),
                    contact_type = COALESCE(?, contact_type),
                    last_seen = COALESCE(?, last_seen)
                WHERE mac = ?
            """, lat, lng, tracker_id, tracker_label, is_paired, pairing_start,
                pairing_duration_sec, battery_percent, magnet_status,
                rssi, contact_type, last_seen_dt, mac)

            old_lat = existing[1] if old_lat is None else old_lat
            old_lng = existing[2] if old_lng is None else old_lng
        else:
            # Insert new position
            print(f"[DB] Inserting BLE position: mac={mac}, lat={lat}, lng={lng}, tracker={tracker_id}")
            cursor.execute("""
                INSERT INTO BLE_Positions
                (mac, lat, lng, last_tracker_id, last_tracker_label, is_paired,
                 pairing_start, pairing_duration_sec, battery_percent, magnet_status,
                 rssi, contact_type, last_seen)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, mac, lat, lng, tracker_id, tracker_label, is_paired,
                pairing_start, pairing_duration_sec, battery_percent, magnet_status,
                rssi, contact_type, last_seen_dt)
            print(f"[DB] Insert executed, rowcount={cursor.rowcount}")
        
        # Log movement if requested and position changed
        if log_movement and old_lat is not None and old_lng is not None:
            distance = _calculate_distance(old_lat, old_lng, lat, lng)
            if distance > 10:  # Only log if moved more than 10 meters
                cursor.execute("""
                    INSERT INTO BLE_Movement_Log 
                    (mac, from_lat, from_lng, to_lat, to_lng, distance_meters,
                     tracker_id, tracker_label, pairing_duration_sec)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, mac, old_lat, old_lng, lat, lng, distance,
                    tracker_id, tracker_label, pairing_duration_sec)
        
        conn.commit()
        print(f"[DB] Committed BLE position: {mac}")
        return True
    except Exception as e:
        print(f"[DB ERROR] update_ble_position: {e}")
        import traceback
        traceback.print_exc()
        return False


def update_ble_heartbeat(
    mac: str,
    battery_percent=None,
    battery_voltage: float = None,
    temperature: float = None,
    humidity: float = None,
    tracker_id=None,
    tracker_label: str = None,
    rssi: float = None,
    last_seen_navixy: str = None,
) -> bool:
    """
    Lightweight heartbeat update: refresh last_update, battery, rssi, temp, humidity on every detection.
    Does NOT change lat/lng position - only updates metadata.
    Called on every beacon scan so popup always shows fresh 'Last seen at'.
    """
    try:
        conn = get_connection()
        cursor = conn.cursor()
        mac = mac.lower()

        last_seen_dt = None
        if last_seen_navixy:
            try:
                last_seen_dt = datetime.strptime(str(last_seen_navixy)[:19], "%Y-%m-%d %H:%M:%S")
            except Exception:
                pass

        cursor.execute("""
            UPDATE BLE_Positions
            SET last_update        = GETDATE(),
                battery_percent    = COALESCE(?, battery_percent),
                battery_voltage    = COALESCE(?, battery_voltage),
                temperature        = COALESCE(?, temperature),
                humidity           = COALESCE(?, humidity),
                last_tracker_id    = COALESCE(?, last_tracker_id),
                last_tracker_label = COALESCE(?, last_tracker_label),
                rssi               = COALESCE(?, rssi),
                last_seen          = COALESCE(?, last_seen)
            WHERE mac = ?
        """, battery_percent, battery_voltage, temperature, humidity,
            str(tracker_id) if tracker_id else None, tracker_label,
            rssi, last_seen_dt, mac)
        conn.commit()
        return cursor.rowcount > 0
    except Exception as e:
        print(f"[DB ERROR] update_ble_heartbeat: {e}")
        return False


def log_pairing(
    mac: str,
    tracker_id,  # Can be int or str (IMEI)
    tracker_label: str,
    pairing_start: datetime,
    pairing_end: datetime,
    start_lat: float,
    start_lng: float,
    end_lat: float,
    end_lng: float
) -> bool:
    """Log a completed pairing session"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        
        duration = int((pairing_end - pairing_start).total_seconds())
        distance = _calculate_distance(start_lat, start_lng, end_lat, end_lng)
        
        cursor.execute("""
            INSERT INTO BLE_Pairing_History
            (mac, tracker_id, tracker_label, pairing_start, pairing_end, duration_sec,
             start_lat, start_lng, end_lat, end_lng, distance_traveled)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, mac.lower(), tracker_id, tracker_label, pairing_start, pairing_end,
            duration, start_lat, start_lng, end_lat, end_lng, distance)
        
        conn.commit()
        return True
    except Exception as e:
        print(f"[DB ERROR] log_pairing: {e}")
        return False


def update_beacon_battery(mac: str, battery_percent=None, magnet_status: str = None) -> bool:
    """Update ONLY battery/magnet for a beacon — never touches is_paired, contact_type, or position."""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE BLE_Positions
            SET battery_percent = COALESCE(?, battery_percent),
                magnet_status   = COALESCE(?, magnet_status),
                last_update     = GETDATE()
            WHERE mac = ?
        """, battery_percent, magnet_status, mac.lower())
        conn.commit()
        return True
    except Exception as e:
        print(f"[DB ERROR] update_beacon_battery({mac}): {e}")
        return False


def get_beacon_contact_type(mac: str) -> str:
    """Get the current contact_type for a beacon MAC. Returns None if not found."""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT contact_type FROM BLE_Positions WHERE mac = ?", mac)
        row = cursor.fetchone()
        if row:
            return str(row[0]) if row[0] else None
        return None
    except Exception as e:
        print(f"[DB ERROR] get_beacon_contact_type({mac}): {e}")
        return None


def get_tracker_by_imei(imei: str) -> dict:
    """Look up a tracker row by IMEI. Returns dict with 'id' and 'label', or None if not found."""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, label FROM Trackers WHERE imei = ?", imei)
        row = cursor.fetchone()
        if row:
            return {"id": int(row[0]), "label": str(row[1])}
        return None
    except Exception as e:
        print(f"[DB ERROR] get_tracker_by_imei({imei}): {e}")
        return None


def update_tracker(
    tracker_id: int,
    label: str,
    lat: float,
    lng: float,
    speed: float = None,
    device_type: str = None,
    category: str = None,
    battery_percent: int = None,
    imei: str = None,
    connection_status: str = None,
    movement_status: str = None,
    ignition = None,
    gps_signal: int = None,
    gsm_signal: int = None,
    engine_hours: float = None,
    odometer: float = None,
) -> bool:
    """Update or insert tracker position and full state"""
    try:
        conn = get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT id FROM Trackers WHERE id = ?", tracker_id)
        exists = cursor.fetchone()

        if exists:
            cursor.execute("""
                UPDATE Trackers
                SET label = ?, lat = ?, lng = ?, speed = ?, last_update = GETDATE(),
                    battery_percent = ?,
                    imei              = COALESCE(?, imei),
                    connection_status = COALESCE(?, connection_status),
                    movement_status   = COALESCE(?, movement_status),
                    ignition          = COALESCE(?, ignition),
                    gps_signal        = COALESCE(?, gps_signal),
                    gsm_signal        = COALESCE(?, gsm_signal),
                    engine_hours      = COALESCE(?, engine_hours),
                    odometer          = COALESCE(?, odometer)
                WHERE id = ?
            """, label, lat, lng, speed, battery_percent,
                imei, connection_status, movement_status,
                ignition, gps_signal, gsm_signal, engine_hours, odometer,
                tracker_id)
        else:
            cursor.execute("""
                INSERT INTO Trackers
                (id, label, lat, lng, speed, device_type, category, battery_percent,
                 imei, connection_status, movement_status, ignition,
                 gps_signal, gsm_signal, engine_hours, odometer)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, tracker_id, label, lat, lng, speed, device_type, category, battery_percent,
                imei, connection_status, movement_status, ignition,
                gps_signal, gsm_signal, engine_hours, odometer)

        conn.commit()
        return True
    except Exception as e:
        print(f"[DB ERROR] update_tracker: {e}")
        return False


def log_tracker_state(
    tracker_id: int,
    label: str,
    imei: str = None,
    lat: float = None,
    lng: float = None,
    speed: float = None,
    connection_status: str = None,
    movement_status: str = None,
    ignition = None,
    battery_level: int = None,
    gps_signal: int = None,
    gsm_signal: int = None,
    engine_hours: float = None,
    odometer: float = None,
) -> bool:
    """
    Insert one time-series row into Tracker_State_Log.
    Called on every /data poll so we build a full history of tracker state.
    """
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO Tracker_State_Log
            (tracker_id, label, imei, lat, lng, speed,
             connection_status, movement_status, ignition,
             battery_level, gps_signal, gsm_signal, engine_hours, odometer)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, tracker_id, label, imei, lat, lng, speed,
            connection_status, movement_status, ignition,
            battery_level, gps_signal, gsm_signal, engine_hours, odometer)
        conn.commit()
        return True
    except Exception as e:
        print(f"[DB ERROR] log_tracker_state: {e}")
        return False


def log_ble_detection(
    mac: str,
    lat: float,
    lng: float,
    tracker_id: int = None,
    tracker_imei: str = None,
    tracker_label: str = None,
    rssi: float = None,
    battery_percent = None,
    battery_voltage: float = None,
    temperature: float = None,
    humidity: float = None,
    is_known_beacon: bool = False,
    contact_type: str = None,
    pairing_duration_sec: int = None,
) -> bool:
    """
    Insert one time-series row into BLE_Scans for every Navixy beacon detection.
    Records full history: who saw which beacon, when, where, signal, battery, temp, humidity.
    """
    try:
        conn = get_connection()
        cursor = conn.cursor()
        battery_int = None
        if battery_percent is not None:
            try:
                battery_int = int(float(battery_percent))
            except (TypeError, ValueError):
                pass
        cursor.execute("""
            INSERT INTO BLE_Scans
            (mac, lat, lng, tracker_imei, tracker_label, tracker_id,
             rssi, battery_percent, battery_voltage, temperature, humidity,
             is_known_beacon, contact_type, pairing_duration_sec, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'navixy')
        """, mac.lower(), lat, lng, tracker_imei, tracker_label, tracker_id,
            rssi, battery_int, battery_voltage, temperature, humidity,
            int(bool(is_known_beacon)), contact_type, pairing_duration_sec)
        conn.commit()
        return True
    except Exception as e:
        print(f"[DB ERROR] log_ble_detection: {e}")
        return False


def get_config(key: str, default: str = None) -> str:
    """Get a configuration value"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT config_value FROM System_Config WHERE config_key = ?", key)
        row = cursor.fetchone()
        return row[0] if row else default
    except Exception as e:
        print(f"[DB ERROR] get_config: {e}")
        return default


def _calculate_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate distance between two points in meters using Haversine formula"""
    from math import radians, cos, sin, asin, sqrt
    
    lat1, lng1, lat2, lng2 = map(radians, [lat1, lng1, lat2, lng2])
    dlat = lat2 - lat1
    dlng = lng2 - lng1
    
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlng/2)**2
    c = 2 * asin(sqrt(a))
    r = 6371000  # Radius of Earth in meters
    
    return c * r


# Test connection on import
if __name__ == "__main__":
    print("Testing database connection...")
    try:
        conn = get_connection()
        print("[OK] Connected to SQL Server")
        
        defs = get_ble_definitions()
        print(f"[OK] Found {len(defs)} BLE definitions")
        for mac, info in defs.items():
            print(f"  - {info['name']} ({mac})")
        
        positions = get_all_ble_positions()
        print(f"[OK] Found {len(positions)} BLE positions")
        
    except Exception as e:
        print(f"[ERROR] {e}")
