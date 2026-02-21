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
        # All columns are directly in BLE_Positions table
        cursor.execute("""
            SELECT mac, lat, lng, last_tracker_id, last_tracker_label, 
                   last_update, is_paired, pairing_start, pairing_duration_sec,
                   battery_percent, magnet_status, name, category, ble_type, serial_number
            FROM BLE_Positions
        """)
        
        positions = {}
        for row in cursor.fetchall():
            mac = row[0].lower() if row[0] else ""
            positions[mac] = {
                "lat": float(row[1]) if row[1] is not None else None,
                "lng": float(row[2]) if row[2] is not None else None,
                "last_tracker_id": str(row[3]) if row[3] else None,
                "last_tracker_label": row[4],
                "last_update": row[5].isoformat() if row[5] else None,
                "is_paired": bool(row[6]) if row[6] is not None else False,
                "pairing_start": row[7].isoformat() if row[7] else None,
                "pairing_duration_sec": row[8],
                "battery_percent": row[9],
                "magnet_status": row[10],
                "name": row[11],
                "category": row[12],
                "type": row[13],
                "sn": row[14],
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
    battery_percent: int = None,
    magnet_status: str = None,
    log_movement: bool = False,
    old_lat: float = None,
    old_lng: float = None
) -> bool:
    """Update or insert BLE position"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        mac = mac.lower()
        
        # Check if position exists
        cursor.execute("SELECT id, lat, lng FROM BLE_Positions WHERE mac = ?", mac)
        existing = cursor.fetchone()
        
        if existing:
            # Update existing position
            cursor.execute("""
                UPDATE BLE_Positions
                SET lat = ?, lng = ?, last_tracker_id = ?, last_tracker_label = ?,
                    last_update = GETDATE(), is_paired = ?, pairing_start = ?,
                    pairing_duration_sec = ?, battery_percent = ?, magnet_status = ?
                WHERE mac = ?
            """, lat, lng, tracker_id, tracker_label, is_paired, pairing_start,
                pairing_duration_sec, battery_percent, magnet_status, mac)
            
            old_lat = existing[1] if old_lat is None else old_lat
            old_lng = existing[2] if old_lng is None else old_lng
        else:
            # Insert new position
            print(f"[DB] Inserting BLE position: mac={mac}, lat={lat}, lng={lng}, tracker={tracker_id}")
            cursor.execute("""
                INSERT INTO BLE_Positions 
                (mac, lat, lng, last_tracker_id, last_tracker_label, is_paired, 
                 pairing_start, pairing_duration_sec, battery_percent, magnet_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, mac, lat, lng, tracker_id, tracker_label, is_paired,
                pairing_start, pairing_duration_sec, battery_percent, magnet_status)
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


def update_tracker(
    tracker_id: int,
    label: str,
    lat: float,
    lng: float,
    speed: float = None,
    device_type: str = None,
    category: str = None,
    battery_percent: int = None
) -> bool:
    """Update or insert tracker position"""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        
        cursor.execute("SELECT id FROM Trackers WHERE id = ?", tracker_id)
        exists = cursor.fetchone()
        
        if exists:
            cursor.execute("""
                UPDATE Trackers
                SET label = ?, lat = ?, lng = ?, speed = ?, last_update = GETDATE(),
                    battery_percent = ?
                WHERE id = ?
            """, label, lat, lng, speed, battery_percent, tracker_id)
        else:
            cursor.execute("""
                INSERT INTO Trackers 
                (id, label, lat, lng, speed, device_type, category, battery_percent)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, tracker_id, label, lat, lng, speed, device_type, category, battery_percent)
        
        conn.commit()
        return True
    except Exception as e:
        print(f"[DB ERROR] update_tracker: {e}")
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
