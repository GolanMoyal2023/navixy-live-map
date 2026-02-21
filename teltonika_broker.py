#!/usr/bin/env python3
"""
Teltonika TCP/HTTP Broker
Receives data directly from Teltonika FMC650/FMC003 devices,
parses CODEC8 protocol, extracts BLE beacons, applies 60-second
pairing logic, and stores data in SQL Server.

Ports:
- TCP 15027: Teltonika device connections (CODEC8)
- HTTP 8768: API endpoint for map (/data)
"""

import socket
import struct
import threading
import time
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from collections import defaultdict
from flask import Flask, jsonify
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)

# Import database helper
try:
    import db_helper
    DB_ENABLED = True
    logger.info("[DB] SQL Server integration enabled")
except Exception as e:
    DB_ENABLED = False
    logger.warning(f"[DB] SQL Server disabled: {e}")

# ============================================================
# CONFIGURATION
# ============================================================
TCP_HOST = "0.0.0.0"
TCP_PORT = 15027  # Teltonika devices connect here
HTTP_PORT = 8768  # Map API endpoint

# Position update configuration - CONSERVATIVE FOR STABILITY
PAIRING_THRESHOLD_SEC = 60      # 60 seconds for towing confirmation (STABLE)
GPS_DRIFT_THRESHOLD_M = 30      # Ignore movements < 30m (GPS drift filter)
GAP_THRESHOLD_SEC = 300         # 5 minutes = detection gap (assets don't move often)
SIGNIFICANT_MOVE_M = 100        # Movement > 100m after gap = confirmed new placement
MAX_SPEED_KMH = 5               # Only update position when speed < 5 km/h (stopped/slow)

# STABILITY MODE: Only update position on VERY clear towing events
STABILITY_MODE = True

# ============================================================
# DATA STORAGE (In-memory + SQL Server)
# ============================================================
# Tracker data: { imei: { lat, lng, speed, timestamp, beacons: [...] } }
trackers: Dict[str, Dict[str, Any]] = {}

# BLE positions: { mac: { lat, lng, tracker_imei, last_update, is_paired } }
ble_positions: Dict[str, Dict[str, Any]] = {}

# BLE pairing tracking: { mac: { tracker_imei, start_time } }
ble_pairing: Dict[str, Dict[str, Any]] = {}

# Known BLE definitions - YOUR 5 BEACONS
# Only these will be tracked, all others ignored
ble_definitions: Dict[str, Dict[str, Any]] = {
    # Full MACs (lowercase)
    "7cd9f407f95c": {"name": "Eybe2plus1", "category": "Towed Device", "type": "eye_beacon", "sn": "6204011070"},
    "7cd9f4003536": {"name": "Eybe2plus2", "category": "Equipment", "type": "eye_beacon", "sn": "6204011168"},
    "7cd9f4116ee7": {"name": "Eysen2plus", "category": "Safety", "type": "eye_sensor", "sn": "6134010143"},
    # New beacons added
    "7cd9f406427b": {"name": "EyeBe3", "category": "Equipment", "type": "eye_beacon", "sn": ""},
    "7cd9f407a2db": {"name": "EyeBe4", "category": "Equipment", "type": "eye_beacon", "sn": ""},
}

# Partial MAC patterns to match (for different CODEC8 formats)
KNOWN_MAC_PATTERNS = [
    "7cd9f407f95c", "7cd9f4003536", "7cd9f4116ee7", "7cd9f406427b", "7cd9f407a2db",  # Full
    "7cd9f407", "7cd9f400", "7cd9f411", "7cd9f406",  # 8-char prefix
    "f407f95c", "f4003536", "f4116ee7", "f406427b", "f407a2db",  # 8-char suffix
]

def match_known_beacon(mac: str, debug: bool = True) -> Optional[str]:
    """Match a detected MAC to a known beacon, return full MAC if matched"""
    original_mac = mac
    mac = mac.lower().replace(":", "").replace("-", "")
    
    # Remove leading zeros (but keep at least 4 chars)
    mac_stripped = mac.lstrip("0")
    if len(mac_stripped) < 4:
        return None  # Too short, likely garbage data
    
    # Direct match
    if mac in ble_definitions:
        return mac
    
    # Check ALL known beacons (5 total)
    all_known_macs = list(ble_definitions.keys())
    
    for full_mac in all_known_macs:
        full_stripped = full_mac.lstrip("0")
        
        if mac in full_mac or full_mac in mac:
            if debug:
                logger.info(f"MATCH: {original_mac} -> {full_mac} (contains)")
            return full_mac
        
        if mac_stripped in full_stripped or full_stripped in mac_stripped:
            if debug:
                logger.info(f"MATCH: {original_mac} -> {full_mac} (stripped contains)")
            return full_mac
        
        # Check if first 8 chars match (FMC003 truncates MACs)
        mac_8 = mac_stripped[:8] if len(mac_stripped) >= 8 else mac_stripped
        full_8 = full_mac[:8]
        if mac_8 == full_8:
            if debug:
                logger.info(f"MATCH: {original_mac} -> {full_mac} (prefix 8)")
            return full_mac
        
        # Reverse the MAC and check
        mac_reversed = ''.join(reversed([mac[i:i+2] for i in range(0, len(mac), 2)]))
        if mac_reversed in full_mac or full_mac in mac_reversed:
            if debug:
                logger.info(f"MATCH: {original_mac} (rev: {mac_reversed}) -> {full_mac}")
            return full_mac
    
    # Special pattern matching for truncated/reversed MACs
    # Be STRICT - require unique portions of the MAC to avoid false matches
    
    # Eybe2plus2 (7cd9f4003536) - look for "003536" or "f4003" specifically
    if "003536" in mac or "f40035" in mac or "3536" in mac[-6:]:
        logger.info(f"MATCH: {original_mac} -> 7cd9f4003536 (strict 3536 pattern)")
        return "7cd9f4003536"
    
    # EyeBe3 (7cd9f406427b) - look for "f406" prefix (unique among our beacons)
    if "f406" in mac or "9f406" in mac or "d9f406" in mac:
        logger.info(f"MATCH: {original_mac} -> 7cd9f406427b (f406 prefix)")
        return "7cd9f406427b"
    
    # EyeBe4 (7cd9f407a2db) - look for "07a2db" or "a2db" specifically  
    if "07a2db" in mac or "a2db" in mac or "f407a2" in mac:
        logger.info(f"MATCH: {original_mac} -> 7cd9f407a2db (strict a2db pattern)")
        return "7cd9f407a2db"
    
    # Note: 0bf400140300 is NOT Eybe2plus2 - it's a different beacon
    
    # Also check for 3536 pattern (for Eybe2plus2)
    if "3536" in mac or "0035" in mac:
        if debug:
            logger.info(f"MATCH: {original_mac} -> 7cd9f4003536 (contains 3536)")
        return "7cd9f4003536"
    
    # Debug: log unmatched MACs that look interesting
    if debug and ("7cd9" in mac or "f407" in mac or "f400" in mac or "f411" in mac or "3536" in mac):
        logger.info(f"NEAR-MATCH: {original_mac} - consider adding to known beacons")
    
    return None  # Not a known beacon

# Thread lock for data access
data_lock = threading.Lock()

# ============================================================
# CODEC8 PARSER
# ============================================================
class Codec8Parser:
    """Parser for Teltonika CODEC8 Extended protocol"""
    
    # AVL IO Element IDs for BLE Beacons
    BLE_BEACON_IDS = {
        385: "ble_beacons_seen",      # Beacon array
        386: "ble_beacon_1",
        387: "ble_beacon_2", 
        388: "ble_beacon_3",
        389: "ble_beacon_4",
        # Eye Beacon specific
        548: "eye_beacon_battery",
        549: "eye_beacon_temperature",
        550: "eye_beacon_humidity",
        551: "eye_beacon_magnet_1",
        552: "eye_beacon_magnet_2",
        553: "eye_beacon_magnet_3",
        554: "eye_beacon_magnet_4",
    }
    
    @staticmethod
    def parse_packet(data: bytes) -> Dict[str, Any]:
        """Parse a complete CODEC8 packet"""
        result = {
            "success": False,
            "records": [],
            "imei": None,
        }
        
        try:
            if len(data) < 12:
                return result
            
            # Parse preamble
            preamble = struct.unpack(">I", data[0:4])[0]
            if preamble != 0:
                logger.debug(f"Invalid preamble: {preamble}")
                return result
            
            # Data length
            data_length = struct.unpack(">I", data[4:8])[0]
            
            # Codec ID
            codec_id = data[8]
            if codec_id not in (0x08, 0x8E):  # CODEC8 or CODEC8 Extended
                logger.debug(f"Unsupported codec: {codec_id}")
                return result
            
            # Number of records
            num_records_1 = data[9]
            
            # Parse AVL records
            offset = 10
            records = []
            
            for i in range(num_records_1):
                if offset + 24 > len(data):
                    break
                    
                record, new_offset = Codec8Parser._parse_avl_record(data, offset, codec_id == 0x8E)
                if record:
                    records.append(record)
                offset = new_offset
            
            result["success"] = True
            result["records"] = records
            
        except Exception as e:
            logger.error(f"Parse error: {e}")
        
        return result
    
    @staticmethod
    def _parse_avl_record(data: bytes, offset: int, extended: bool) -> tuple:
        """Parse single AVL record"""
        try:
            # Timestamp (8 bytes)
            timestamp_ms = struct.unpack(">Q", data[offset:offset+8])[0]
            timestamp = datetime.utcfromtimestamp(timestamp_ms / 1000)
            offset += 8
            
            # Priority (1 byte)
            priority = data[offset]
            offset += 1
            
            # GPS Element (15 bytes)
            lng = struct.unpack(">i", data[offset:offset+4])[0] / 10000000.0
            offset += 4
            lat = struct.unpack(">i", data[offset:offset+4])[0] / 10000000.0
            offset += 4
            altitude = struct.unpack(">H", data[offset:offset+2])[0]
            offset += 2
            angle = struct.unpack(">H", data[offset:offset+2])[0]
            offset += 2
            satellites = data[offset]
            offset += 1
            speed = struct.unpack(">H", data[offset:offset+2])[0]
            offset += 2
            
            record = {
                "timestamp": timestamp.isoformat(),
                "lat": lat,
                "lng": lng,
                "altitude": altitude,
                "angle": angle,
                "satellites": satellites,
                "speed": speed,
                "beacons": [],
                "io_elements": {},
            }
            
            # IO Elements
            if extended:
                # CODEC8 Extended - event ID is 2 bytes
                event_id = struct.unpack(">H", data[offset:offset+2])[0]
                offset += 2
                total_elements = struct.unpack(">H", data[offset:offset+2])[0]
                offset += 2
            else:
                # CODEC8 - event ID is 1 byte
                event_id = data[offset]
                offset += 1
                total_elements = data[offset]
                offset += 1
            
            record["event_id"] = event_id
            
            # Parse IO elements by size
            for size in [1, 2, 4, 8]:
                if extended:
                    count = struct.unpack(">H", data[offset:offset+2])[0]
                    offset += 2
                else:
                    count = data[offset]
                    offset += 1
                
                for _ in range(count):
                    if extended:
                        io_id = struct.unpack(">H", data[offset:offset+2])[0]
                        offset += 2
                    else:
                        io_id = data[offset]
                        offset += 1
                    
                    value = int.from_bytes(data[offset:offset+size], 'big')
                    offset += size
                    
                    record["io_elements"][io_id] = value
            
            # Variable length elements (CODEC8 Extended only)
            if extended:
                count = struct.unpack(">H", data[offset:offset+2])[0]
                offset += 2
                
                # DEBUG: Log variable length element count
                if count > 0:
                    logger.info(f"[DEBUG] Variable length elements: {count}")
                
                for _ in range(count):
                    io_id = struct.unpack(">H", data[offset:offset+2])[0]
                    offset += 2
                    length = struct.unpack(">H", data[offset:offset+2])[0]
                    offset += 2
                    value = data[offset:offset+length]
                    offset += length
                    
                    # DEBUG: Log ALL variable length elements
                    if io_id in (385, 10828, 10829, 10831, 11317, 548):
                        logger.info(f"[DEBUG] VarLen Element ID={io_id}, Len={length}, Data={value[:40].hex() if len(value) > 40 else value.hex()}")
                    
                    # Parse BLE beacon data - Element 385 (standard) or FMC003 custom elements
                    if io_id == 385:  # Standard BLE Beacons seen
                        logger.info(f"[DEBUG] ELEMENT 385 FOUND! Length={length}")
                        beacons = Codec8Parser._parse_ble_beacons(value)
                        record["beacons"].extend(beacons)
                    elif io_id in (10828, 10829):  # FMC003 custom EYE beacon elements
                        # Parse FMC003 custom beacon format
                        beacons = Codec8Parser._parse_fmc003_beacons(value, io_id)
                        if beacons:
                            record["beacons"].extend(beacons)
                    elif io_id == 11317:  # FMC003 beacon list with names
                        beacons = Codec8Parser._parse_fmc003_beacon_list(value)
                        if beacons:
                            record["beacons"].extend(beacons)
                    else:
                        record["io_elements"][io_id] = value.hex()
            
            return record, offset
            
        except Exception as e:
            logger.error(f"AVL record parse error: {e}")
            return None, offset + 50  # Skip some bytes
    
    @staticmethod
    def _parse_fmc003_beacons(data: bytes, element_id: int) -> List[Dict[str, Any]]:
        """Parse FMC003 custom EYE beacon elements (10828, 10829)"""
        beacons = []
        try:
            if len(data) < 10:
                return beacons
            
            # FMC003 format: data contains MAC addresses embedded
            # Look for known MAC patterns in the raw data
            data_hex = data.hex().lower()
            
            # Search for known beacon MAC patterns
            known_macs = ["7cd9f407f95c", "7cd9f407a2db", "7cd9f4003536", "7cd9f4116ee7", "7cd9f406427b"]
            
            for mac in known_macs:
                if mac in data_hex:
                    # Found a beacon MAC!
                    logger.info(f"[FMC003] Found beacon MAC in element {element_id}: {mac}")
                    
                    # Try to extract battery from nearby bytes
                    mac_pos = data_hex.find(mac)
                    battery = None
                    if mac_pos >= 4:
                        # Battery might be 2 bytes before MAC
                        try:
                            battery_hex = data_hex[mac_pos-4:mac_pos-2]
                            battery = int(battery_hex, 16)
                        except:
                            pass
                    
                    beacon = {
                        "mac": mac,
                        "battery": battery,
                        "rssi": None,
                        "detected_at": datetime.now().isoformat(),
                        "source": f"element_{element_id}",
                    }
                    beacons.append(beacon)
            
        except Exception as e:
            logger.error(f"FMC003 beacon parse error: {e}")
        
        return beacons
    
    @staticmethod
    def _parse_fmc003_beacon_list(data: bytes) -> List[Dict[str, Any]]:
        """Parse FMC003 element 11317 (beacon list with names)"""
        beacons = []
        try:
            if len(data) < 20:
                return beacons
            
            data_hex = data.hex().lower()
            
            # Search for known beacon MAC patterns
            known_macs = ["7cd9f407f95c", "7cd9f407a2db", "7cd9f4003536", "7cd9f4116ee7", "7cd9f406427b"]
            
            for mac in known_macs:
                if mac in data_hex:
                    logger.info(f"[FMC003] Found beacon MAC in element 11317: {mac}")
                    beacon = {
                        "mac": mac,
                        "battery": None,
                        "rssi": None,
                        "detected_at": datetime.now().isoformat(),
                        "source": "element_11317",
                    }
                    beacons.append(beacon)
                    
        except Exception as e:
            logger.error(f"FMC003 beacon list parse error: {e}")
        
        return beacons

    @staticmethod
    def _parse_ble_beacons(data: bytes) -> List[Dict[str, Any]]:
        """Parse BLE beacon array from IO element 385"""
        beacons = []
        try:
            if len(data) < 1:
                return beacons
            
            num_beacons = data[0]
            offset = 1
            
            for i in range(num_beacons):
                if offset + 14 > len(data):
                    break
                
                # Beacon data format: MAC (6 bytes) + RSSI (1) + Battery (1) + Flags (1) + ...
                mac_bytes = data[offset:offset+6]
                mac = mac_bytes.hex().lower()
                offset += 6
                
                rssi = struct.unpack("b", bytes([data[offset]]))[0] if offset < len(data) else -100
                offset += 1
                
                # Try to parse more fields if available
                battery = None
                temperature = None
                humidity = None
                magnet_status = None
                
                if offset + 1 <= len(data):
                    battery = data[offset]
                    offset += 1
                
                if offset + 1 <= len(data):
                    flags = data[offset]
                    offset += 1
                    
                    # Parse additional data based on flags
                    if flags & 0x01 and offset + 2 <= len(data):  # Temperature
                        temperature = struct.unpack(">h", data[offset:offset+2])[0] / 100.0
                        offset += 2
                    
                    if flags & 0x02 and offset + 1 <= len(data):  # Humidity
                        humidity = data[offset]
                        offset += 1
                    
                    if flags & 0x04 and offset + 1 <= len(data):  # Magnet sensor
                        magnet_status = data[offset]
                        offset += 1
                
                beacon = {
                    "mac": mac,
                    "rssi": rssi,
                    "battery": battery,
                    "temperature": temperature,
                    "humidity": humidity,
                    "magnet_status": magnet_status,
                    "detected_at": datetime.now().isoformat(),
                }
                beacons.append(beacon)
                
        except Exception as e:
            logger.error(f"BLE beacon parse error: {e}")
        
        return beacons


# ============================================================
# IMPROVED POSITIONING LOGIC
# ============================================================
def calculate_distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate distance between two points in meters using Haversine formula"""
    import math
    R = 6371000  # Earth's radius in meters
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lng = math.radians(lng2 - lng1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def process_beacons(imei: str, tracker_lat: float, tracker_lng: float, beacons: List[Dict[str, Any]], tracker_speed: float = 0):
    """
    Process BLE beacons with IMPROVED positioning logic:
    
    1. SPEED FILTER: Only update position when tracker speed < 5 km/h (stopped/slow)
    2. FIRST DETECTION: Set initial position immediately (if stopped)
    3. GPS DRIFT FILTER: Ignore movements < 25m (prevents static device drift)
    4. GAP + SIGNIFICANT MOVE: If not seen for >5 min AND moved >50m, update immediately
    5. CONTINUOUS PAIRING (60s): For towing detection - update position during towing
    
    This fixes:
    - Beacons getting scattered positions while driving
    - Eyesensor shifting 20m while static (GPS drift)
    - Eyebecon1 not updating after driving home (gap detection)
    """
    global ble_positions, ble_pairing
    
    now = datetime.now()
    known_detected = []  # Track which known beacons were detected
    is_stopped = tracker_speed < MAX_SPEED_KMH  # Only update positions when stopped/slow
    
    # Log all raw MACs for debugging (first 10 only)
    if beacons and len(beacons) > 0:
        raw_macs = [b.get("mac", "?")[:12] for b in beacons[:10]]
        logger.info(f"[DEBUG] ALL Raw MACs received: {raw_macs}, Speed: {tracker_speed:.1f} km/h, Stopped: {is_stopped}")
    
    with data_lock:
        for beacon in beacons:
            raw_mac = beacon.get("mac", "").lower()
            if not raw_mac:
                continue
            
            # Check if this is one of our known beacons
            matched_mac = match_known_beacon(raw_mac, debug=True)
            if not matched_mac:
                # Log unmatched MACs for debugging
                if "f407" in raw_mac or "f400" in raw_mac or "f411" in raw_mac:
                    logger.warning(f"[DEBUG] CLOSE BUT NO MATCH: {raw_mac} (contains known pattern)")
                continue  # Skip unknown beacons
            
            mac = matched_mac  # Use the full known MAC
            known_detected.append(mac)
            
            # Get BLE definition info
            ble_info = ble_definitions.get(mac, {})
            beacon_name = ble_info.get("name", mac[:8])
            beacon["name"] = beacon_name
            beacon["category"] = ble_info.get("category", "Unknown")
            beacon["type"] = ble_info.get("type", "eye_beacon")
            beacon["sn"] = ble_info.get("sn", "")
            
            # ============================================================
            # CASE 1: FIRST DETECTION - Set initial position (ONLY IF STOPPED)
            # ============================================================
            if mac not in ble_positions:
                if is_stopped:
                    # Tracker is stopped - set initial position
                    ble_positions[mac] = {
                        "lat": tracker_lat,
                        "lng": tracker_lng,
                        "tracker_imei": imei,
                        "tracker_label": trackers.get(imei, {}).get("label", imei),
                        "last_update": now.isoformat(),
                        "last_seen": now,  # datetime object for calculations
                        "is_paired": False,
                        "pairing_duration": 0,
                        "battery": beacon.get("battery"),
                        "rssi": beacon.get("rssi"),
                        "magnet_status": beacon.get("magnet_status"),
                    }
                    ble_pairing[mac] = {"tracker_imei": imei, "start_time": now}
                    logger.info(f"BLE {mac} ({beacon_name}): FIRST DETECTION (STOPPED) at ({tracker_lat:.6f}, {tracker_lng:.6f})")
                else:
                    # Tracker is moving - DON'T set position yet, just track that we saw it
                    ble_positions[mac] = {
                        "lat": None,  # No position yet - waiting for stop
                        "lng": None,
                        "tracker_imei": imei,
                        "tracker_label": trackers.get(imei, {}).get("label", imei),
                        "last_update": now.isoformat(),
                        "last_seen": now,
                        "is_paired": False,
                        "pairing_duration": 0,
                        "battery": beacon.get("battery"),
                        "rssi": beacon.get("rssi"),
                        "magnet_status": beacon.get("magnet_status"),
                    }
                    ble_pairing[mac] = {"tracker_imei": imei, "start_time": now}
                    logger.info(f"BLE {mac} ({beacon_name}): DETECTED WHILE MOVING ({tracker_speed:.1f} km/h) - waiting for stop")
                
                # Save to database
                if DB_ENABLED:
                    try:
                        db_helper.update_ble_position(
                            mac=mac, lat=tracker_lat, lng=tracker_lng,
                            tracker_id=imei, tracker_label=imei,
                            is_paired=False, pairing_duration_sec=0,
                            battery_percent=beacon.get("battery"),
                            magnet_status=str(beacon.get("magnet_status")) if beacon.get("magnet_status") else None,
                        )
                    except Exception as e:
                        logger.error(f"[DB] Error saving first position: {e}")
                continue
            
            # ============================================================
            # EXISTING BEACON - Calculate distance and time since last seen
            # ============================================================
            old_lat = ble_positions[mac].get("lat", tracker_lat)
            old_lng = ble_positions[mac].get("lng", tracker_lng)
            distance_m = calculate_distance_meters(old_lat, old_lng, tracker_lat, tracker_lng)
            
            # Calculate time since last seen
            last_seen = ble_positions[mac].get("last_seen")
            if isinstance(last_seen, str):
                try:
                    last_seen = datetime.fromisoformat(last_seen)
                except:
                    last_seen = now
            gap_seconds = (now - last_seen).total_seconds() if last_seen else 0
            
            # Always update metadata (runs every detection, regardless of distance)
            ble_positions[mac]["last_seen"] = now
            ble_positions[mac]["last_update"] = now.isoformat()
            ble_positions[mac]["battery"] = beacon.get("battery") or ble_positions[mac].get("battery")
            ble_positions[mac]["rssi"] = beacon.get("rssi") or ble_positions[mac].get("rssi")
            ble_positions[mac]["tracker_imei"] = imei
            if beacon.get("magnet_status") is not None:
                ble_positions[mac]["magnet_status"] = beacon.get("magnet_status")
            
            # ============================================================
            # CASE 1b: BEACON HAS NO POSITION YET (was detected while moving)
            # ============================================================
            if old_lat is None or old_lng is None:
                if is_stopped:
                    # Now stopped - set the position!
                    ble_positions[mac]["lat"] = tracker_lat
                    ble_positions[mac]["lng"] = tracker_lng
                    logger.info(f"BLE {mac} ({beacon_name}): NOW STOPPED - setting position ({tracker_lat:.6f}, {tracker_lng:.6f})")
                    if DB_ENABLED:
                        try:
                            db_helper.update_ble_position(
                                mac=mac, lat=tracker_lat, lng=tracker_lng,
                                tracker_id=imei, tracker_label=imei,
                                is_paired=False, pairing_duration_sec=0,
                                battery_percent=beacon.get("battery"),
                                magnet_status=str(beacon.get("magnet_status")) if beacon.get("magnet_status") else None,
                            )
                        except Exception as e:
                            logger.error(f"[DB] Error setting position: {e}")
                else:
                    logger.debug(f"BLE {mac}: Still moving ({tracker_speed:.1f} km/h), waiting for stop")
                continue
            
            # ============================================================
            # PAIRING STATUS - Always update regardless of distance
            # Runs BEFORE the drift filter so map status is always current
            # ============================================================
            current_pairing = ble_pairing.get(mac)

            if current_pairing is None or current_pairing.get("tracker_imei") != imei:
                # New or different tracker - reset pairing timer
                ble_pairing[mac] = {"tracker_imei": imei, "start_time": now}
                logger.info(f"BLE {mac} ({beacon_name}): New tracker {imei}, starting 60s pairing timer")
                ble_positions[mac]["is_paired"] = False
                ble_positions[mac]["pairing_duration"] = 0
                pairing_duration = 0
                is_paired = False
            else:
                # Same tracker - accumulate pairing duration
                pairing_duration = (now - ble_pairing[mac]["start_time"]).total_seconds()
                ble_positions[mac]["pairing_duration"] = int(pairing_duration)
                is_paired = pairing_duration >= PAIRING_THRESHOLD_SEC
                ble_positions[mac]["is_paired"] = is_paired
                if not is_paired:
                    logger.debug(f"BLE {mac}: Pairing {pairing_duration:.0f}s / {PAIRING_THRESHOLD_SEC}s")

            # ============================================================
            # CASE 2: GPS DRIFT FILTER - Skip position update only
            # Pairing status already updated above - map always stays current
            # ============================================================
            if distance_m < GPS_DRIFT_THRESHOLD_M:
                logger.debug(f"BLE {mac}: No movement ({distance_m:.1f}m), paired={is_paired}, duration={int(pairing_duration)}s")
                continue

            # ============================================================
            # CASE 3: GAP + SIGNIFICANT MOVE - Update immediately
            # ============================================================
            if gap_seconds > GAP_THRESHOLD_SEC and distance_m > SIGNIFICANT_MOVE_M:
                logger.info(f"BLE {mac} ({beacon_name}): GAP ({gap_seconds:.0f}s) + MOVED {distance_m:.0f}m -> UPDATING")
                ble_positions[mac]["lat"] = tracker_lat
                ble_positions[mac]["lng"] = tracker_lng
                ble_positions[mac]["is_paired"] = True
                ble_pairing[mac] = {"tracker_imei": imei, "start_time": now}
                pairing_duration = 0
                is_paired = True
                if DB_ENABLED:
                    try:
                        db_helper.update_ble_position(
                            mac=mac, lat=tracker_lat, lng=tracker_lng,
                            tracker_id=imei, tracker_label=imei,
                            is_paired=True, pairing_duration_sec=int(gap_seconds),
                            battery_percent=beacon.get("battery"),
                            magnet_status=str(beacon.get("magnet_status")) if beacon.get("magnet_status") else None,
                        )
                        logger.info(f"[DB] Updated BLE position after gap: {mac}")
                    except Exception as e:
                        logger.error(f"[DB] Error updating position: {e}")
                continue

            # ============================================================
            # CASE 4: TOWING CONFIRMED - Update position when paired (>60s)
            # Only reached when distance > GPS_DRIFT_THRESHOLD (real movement)
            # ============================================================
            if is_paired:
                logger.info(f"BLE {mac} ({beacon_name}): TOWING ({pairing_duration:.0f}s), moved {distance_m:.0f}m -> UPDATING")
                ble_positions[mac]["lat"] = tracker_lat
                ble_positions[mac]["lng"] = tracker_lng
                if DB_ENABLED:
                    try:
                        db_helper.update_ble_position(
                            mac=mac,
                            lat=tracker_lat,
                            lng=tracker_lng,
                            tracker_id=imei,
                            tracker_label=imei,
                            is_paired=True,
                            pairing_duration_sec=int(pairing_duration),
                            battery_percent=beacon.get("battery"),
                            magnet_status=str(beacon.get("magnet_status")) if beacon.get("magnet_status") else None,
                        )
                        logger.info(f"[DB] Updated BLE position during towing: {mac}")
                    except Exception as e:
                        logger.error(f"DB save error: {e}")
            else:
                logger.debug(f"BLE {mac}: Waiting for 60s pairing ({pairing_duration:.0f}s so far)")
            
            # Update beacon with position info
            pos = ble_positions[mac]
            beacon["stored_lat"] = pos["lat"]
            beacon["stored_lng"] = pos["lng"]
            beacon["is_paired"] = is_paired
            beacon["pairing_duration"] = int(pairing_duration)
            beacon["last_tracker"] = pos.get("tracker_label", imei)
            
            # Log EVERY scan to BLE_Scans for historical analysis
            if DB_ENABLED:
                try:
                    conn = db_helper.get_connection()
                    cursor = conn.cursor()
                    cursor.execute("""
                        INSERT INTO BLE_Scans 
                        (mac, lat, lng, tracker_imei, tracker_label, rssi, battery_percent, 
                         distance_meters, magnet_status, is_known_beacon, scan_time)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, GETDATE())
                    """, mac, tracker_lat, tracker_lng, imei, imei, 
                        beacon.get("rssi"), beacon.get("battery"), 
                        beacon.get("distance", 0),
                        str(beacon.get("magnet_status")) if beacon.get("magnet_status") else None)
                    conn.commit()
                    logger.debug(f"[DB] Scan logged: {mac}")
                except Exception as e:
                    logger.debug(f"[DB] Scan log error: {e}")


# ============================================================
# TCP SERVER (Teltonika Devices)
# ============================================================
def handle_client(client_socket: socket.socket, address: tuple):
    """Handle a Teltonika device connection"""
    imei = None
    logger.info(f"[TCP] Connection from {address}")
    
    try:
        # First, receive IMEI (authentication)
        imei_data = client_socket.recv(256)
        logger.info(f"[TCP] Received {len(imei_data)} bytes for IMEI: {imei_data.hex()[:100]}")
        
        if len(imei_data) >= 2:
            imei_length = struct.unpack(">H", imei_data[0:2])[0]
            logger.info(f"[TCP] IMEI length field: {imei_length}, total bytes: {len(imei_data)}")
            
            if imei_length > 0 and len(imei_data) >= 2 + imei_length:
                imei = imei_data[2:2+imei_length].decode('ascii')
                logger.info(f"[TCP] Device authenticated: IMEI {imei}")
                
                # Send acknowledgment (accept)
                client_socket.send(b'\x01')
                
                # Initialize tracker
                with data_lock:
                    if imei not in trackers:
                        trackers[imei] = {
                            "label": imei,
                            "lat": 0,
                            "lng": 0,
                            "speed": 0,
                            "last_update": None,
                            "beacons": [],
                        }
            else:
                logger.warning(f"[TCP] Invalid IMEI from {address}: length={imei_length}, data_len={len(imei_data)}")
                client_socket.send(b'\x00')
                return
        else:
            logger.warning(f"[TCP] IMEI packet too short from {address}: {len(imei_data)} bytes")
            client_socket.send(b'\x00')
            return
        
        # Receive data packets
        while True:
            try:
                data = client_socket.recv(4096)
                if not data:
                    break
                
                # Log raw data for debugging
                logger.info(f"[TCP] {imei}: Received {len(data)} bytes")
                
                # Parse CODEC8 packet
                result = Codec8Parser.parse_packet(data)
                
                if result["success"] and result["records"]:
                    num_records = len(result["records"])
                    # Log IO elements for debugging
                    for i, rec in enumerate(result["records"]):
                        io_els = rec.get("io_elements", {})
                        beacons_in_rec = rec.get("beacons", [])
                        if io_els or beacons_in_rec:
                            logger.info(f"[TCP] {imei} Record {i}: IOs={list(io_els.keys())[:10]}, Beacons={len(beacons_in_rec)}")
                    
                    # Process each record
                    for record in result["records"]:
                        lat = record.get("lat", 0)
                        lng = record.get("lng", 0)
                        speed = record.get("speed", 0)
                        beacons = record.get("beacons", [])
                        
                        # Update tracker data
                        with data_lock:
                            trackers[imei]["lat"] = lat
                            trackers[imei]["lng"] = lng
                            trackers[imei]["speed"] = speed
                            trackers[imei]["last_update"] = record.get("timestamp")
                            trackers[imei]["beacons"] = beacons
                        
                        # Process BLE beacons with 60-sec pairing logic
                        if beacons:
                            logger.info(f"[TCP] {imei}: {len(beacons)} beacons at ({lat:.6f}, {lng:.6f}), Speed: {speed} km/h")
                            process_beacons(imei, lat, lng, beacons, tracker_speed=speed)
                        
                        # Save tracker to database
                        if DB_ENABLED:
                            try:
                                db_helper.update_tracker(
                                    tracker_id=hash(imei) % 100000,
                                    label=imei,
                                    lat=lat,
                                    lng=lng,
                                    speed=speed
                                )
                            except Exception as e:
                                logger.error(f"DB tracker save error: {e}")
                    
                    # Send acknowledgment (number of records received)
                    ack = struct.pack(">I", num_records)
                    client_socket.send(ack)
                    
            except socket.timeout:
                continue
            except Exception as e:
                logger.error(f"[TCP] Error receiving data: {e}")
                break
                
    except Exception as e:
        logger.error(f"[TCP] Client error: {e}")
    finally:
        client_socket.close()
        logger.info(f"[TCP] Connection closed: {imei or address}")


def tcp_server():
    """Run TCP server for Teltonika devices"""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((TCP_HOST, TCP_PORT))
    server.listen(10)
    
    logger.info(f"[TCP] Teltonika server listening on {TCP_HOST}:{TCP_PORT}")
    
    while True:
        try:
            client, address = server.accept()
            client.settimeout(300)  # 5 minute timeout
            thread = threading.Thread(target=handle_client, args=(client, address))
            thread.daemon = True
            thread.start()
        except Exception as e:
            logger.error(f"[TCP] Accept error: {e}")


# ============================================================
# HTTP API (Flask)
# ============================================================
app = Flask(__name__)

@app.after_request
def add_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response


@app.get("/")
def index():
    return jsonify({
        "service": "Teltonika Direct Broker",
        "tcp_port": TCP_PORT,
        "http_port": HTTP_PORT,
        "trackers": len(trackers),
        "ble_devices": len(ble_positions),
        "db_enabled": DB_ENABLED,
    })


@app.get("/health")
def health():
    return jsonify({"status": "ok", "db_enabled": DB_ENABLED})


@app.get("/data")
def data():
    """Return data in the same format as the Navixy API for map compatibility"""
    with data_lock:
        rows = []
        
        for imei, tracker in trackers.items():
            # Get all beacons currently detected by this tracker
            tracker_beacons = []
            for mac, pos in ble_positions.items():
                if pos.get("tracker_imei") == imei:
                    ble_info = ble_definitions.get(mac, {})
                    tracker_beacons.append({
                        "mac": mac,
                        "name": ble_info.get("name", mac[:8]),
                        "category": ble_info.get("category", "Unknown"),
                        "beaconType": ble_info.get("type", "eye_beacon"),
                        "sn": ble_info.get("sn", ""),
                        "battery": pos.get("battery"),
                        "rssi": pos.get("rssi"),
                        "magnet_sensors": {"status": pos.get("magnet_status")},
                        "last_seen": pos.get("last_update"),
                        "lat": pos.get("lat"),
                        "lng": pos.get("lng"),
                        "hostTrackerId": imei,
                        "hostTrackerLabel": tracker.get("label", imei),
                        "is_paired": pos.get("is_paired", False),
                        "pairing_duration": pos.get("pairing_duration", 0),
                    })
            
            row = {
                "tracker_id": hash(imei) % 100000,
                "label": tracker.get("label", imei),
                "imei": imei,
                "lat": tracker.get("lat"),
                "lng": tracker.get("lng"),
                "speed": tracker.get("speed"),
                "last_update": tracker.get("last_update"),
                "connection_status": "active" if tracker.get("last_update") else "unknown",
                "beacons": tracker_beacons,
            }
            rows.append(row)
        
        # Return ALL known BLEs (from definitions + stored positions)
        # This ensures beacons NEVER disappear from the map
        all_ble = {}
        
        # First, add ALL known BLE definitions (even if no position yet)
        for mac, ble_info in ble_definitions.items():
            all_ble[mac] = {
                "lat": None,  # Will be updated if we have a position
                "lng": None,
                "last_tracker_id": None,
                "last_tracker_label": None,
                "last_update": None,
                "is_paired": False,
                "pairing_duration": 0,
                "battery": None,
                "rssi": None,
                "name": ble_info.get("name", mac[:8]),
                "category": ble_info.get("category", "Unknown"),
                "type": ble_info.get("type", "eye_beacon"),
                "sn": ble_info.get("sn", ""),
            }
        
        # Then, update with stored positions (in-memory - most recent)
        # Only include known BLE definitions — ignore WiFi APs and unknown devices
        for mac, pos in ble_positions.items():
            if mac not in ble_definitions:
                continue  # Skip unknown MACs (WiFi APs, etc.)
            ble_info = ble_definitions.get(mac, {})
            all_ble[mac] = {
                "lat": pos.get("lat"),  # Original position - no offset
                "lng": pos.get("lng"),
                "last_tracker_id": pos.get("tracker_imei"),
                "last_tracker_label": pos.get("tracker_label"),
                "last_update": pos.get("last_update"),
                "is_paired": pos.get("is_paired", False),
                "pairing_duration": pos.get("pairing_duration", 0),
                "battery": pos.get("battery"),
                "rssi": pos.get("rssi"),
                "name": ble_info.get("name", pos.get("name", mac[:8])),
                "category": ble_info.get("category", pos.get("category", "Unknown")),
                "type": ble_info.get("type", pos.get("type", "eye_beacon")),
                "sn": ble_info.get("sn", ""),
            }
        
        # Also fetch from database for any positions we might have missed in memory
        if DB_ENABLED:
            try:
                db_positions = db_helper.get_all_ble_positions()
                for mac, db_pos in db_positions.items():
                    # Only use DB position for KNOWN beacons and only when memory has no position
                    if mac not in ble_definitions:
                        continue  # Skip WiFi APs and unknown MACs stored in DB
                    if mac not in ble_positions or ble_positions[mac].get("lat") is None:
                        ble_info = ble_definitions.get(mac, {})
                        all_ble[mac] = {
                            "lat": db_pos.get("lat"),
                            "lng": db_pos.get("lng"),
                            "last_tracker_id": db_pos.get("last_tracker_id"),
                            "last_tracker_label": db_pos.get("last_tracker_label"),
                            "last_update": db_pos.get("last_update"),
                            "is_paired": db_pos.get("is_paired", False),
                            "pairing_duration": db_pos.get("pairing_duration_sec", 0),
                            "battery": db_pos.get("battery_percent"),
                            "rssi": None,
                            "name": ble_info.get("name", db_pos.get("name", mac[:8])),
                            "category": ble_info.get("category", db_pos.get("category", "Unknown")),
                            "type": ble_info.get("type", db_pos.get("type", "eye_beacon")),
                            "sn": ble_info.get("sn", ""),
                        }
            except Exception as e:
                logger.warning(f"[DB] Could not fetch positions: {e}")
        
        # Log what we're returning
        ble_with_pos = sum(1 for b in all_ble.values() if b.get("lat") is not None)
        logger.debug(f"Returning {len(all_ble)} BLEs ({ble_with_pos} with positions)")
        
        return jsonify({
            "success": True,
            "rows": rows,
            "ble_positions": all_ble,
            "source": "teltonika_direct",
            "db_enabled": DB_ENABLED,
            "ble_count": len(all_ble),
            "ble_with_position": ble_with_pos,
        })


@app.get("/ble/positions")
def get_ble_positions():
    """Get all BLE positions"""
    with data_lock:
        return jsonify({
            "success": True,
            "positions": ble_positions,
            "count": len(ble_positions),
        })


@app.get("/trackers")
def get_trackers():
    """Get all connected trackers"""
    with data_lock:
        return jsonify({
            "success": True,
            "trackers": trackers,
            "count": len(trackers),
        })


@app.get("/api/trackers")
def api_get_trackers():
    """Get all connected trackers (API endpoint for troubleshooting)"""
    with data_lock:
        tracker_list = []
        for imei, data in trackers.items():
            tracker_list.append({
                "imei": imei,
                "lat": data.get("lat"),
                "lng": data.get("lng"),
                "speed": data.get("speed", 0),
                "heading": data.get("heading", 0),
                "timestamp": data.get("timestamp"),
                "beacons": data.get("beacons", [])
            })
        return jsonify(tracker_list)


@app.get("/api/ble")
def api_get_ble():
    """Get all BLE assets (API endpoint for troubleshooting)"""
    with data_lock:
        ble_list = []
        
        # Get all BLE positions
        for mac, pos in ble_positions.items():
            ble_info = ble_definitions.get(mac, {})
            ble_list.append({
                "mac": mac,
                "name": ble_info.get("name", mac[:8]),
                "category": ble_info.get("category", "Unknown"),
                "lat": pos.get("lat"),
                "lng": pos.get("lng"),
                "tracker_imei": pos.get("tracker_imei"),
                "last_update": pos.get("last_update"),
                "is_paired": pos.get("is_paired", False),
                "battery": pos.get("battery"),
                "rssi": pos.get("rssi")
            })
        
        return jsonify({"ble_assets": ble_list})


@app.route("/ble/set-position", methods=["POST"])
def set_ble_position():
    """
    Manually set a BLE beacon position.
    Use when automatic detection is unreliable.
    
    POST body: { "mac": "7cd9f407f95c", "lat": 32.123, "lng": 34.456 }
    """
    from flask import request
    try:
        data = request.get_json()
        mac = data.get("mac", "").lower()
        lat = float(data.get("lat"))
        lng = float(data.get("lng"))
        
        if mac not in ble_definitions:
            return jsonify({"success": False, "error": f"Unknown beacon: {mac}"}), 400
        
        with data_lock:
            ble_info = ble_definitions[mac]
            ble_positions[mac] = {
                "lat": lat,
                "lng": lng,
                "tracker_imei": "manual",
                "tracker_label": "Manual Set",
                "last_update": datetime.now().isoformat(),
                "last_seen": datetime.now(),
                "is_paired": False,
                "pairing_duration": 0,
                "battery": ble_positions.get(mac, {}).get("battery"),
                "rssi": ble_positions.get(mac, {}).get("rssi"),
            }
        
        # Save to database
        if DB_ENABLED:
            try:
                db_helper.update_ble_position(
                    mac=mac, lat=lat, lng=lng,
                    tracker_id="manual", tracker_label="Manual Set",
                    is_paired=False, pairing_duration_sec=0,
                )
                logger.info(f"[MANUAL] Set {mac} ({ble_info.get('name')}) to ({lat}, {lng})")
            except Exception as e:
                logger.error(f"[MANUAL] DB error: {e}")
        
        return jsonify({
            "success": True, 
            "message": f"Set {ble_info.get('name')} to ({lat}, {lng})"
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400


@app.route("/ble/set-all-home", methods=["POST"])
def set_all_home():
    """
    Set ALL beacons to home location.
    Use this to reset after testing.
    
    POST body: { "lat": 32.123, "lng": 34.456 }
    """
    from flask import request
    try:
        data = request.get_json()
        lat = float(data.get("lat"))
        lng = float(data.get("lng"))
        
        updated = []
        with data_lock:
            for mac, ble_info in ble_definitions.items():
                ble_positions[mac] = {
                    "lat": lat,
                    "lng": lng,
                    "tracker_imei": "manual",
                    "tracker_label": "Home Reset",
                    "last_update": datetime.now().isoformat(),
                    "last_seen": datetime.now(),
                    "is_paired": False,
                    "pairing_duration": 0,
                    "battery": ble_positions.get(mac, {}).get("battery"),
                    "rssi": ble_positions.get(mac, {}).get("rssi"),
                }
                updated.append(ble_info.get("name", mac))
                
                if DB_ENABLED:
                    try:
                        db_helper.update_ble_position(
                            mac=mac, lat=lat, lng=lng,
                            tracker_id="manual", tracker_label="Home Reset",
                            is_paired=False, pairing_duration_sec=0,
                        )
                    except:
                        pass
        
        logger.info(f"[MANUAL] Reset ALL {len(updated)} beacons to ({lat}, {lng})")
        return jsonify({
            "success": True,
            "message": f"Reset {len(updated)} beacons to home",
            "beacons": updated
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400


# ============================================================
# RUTX11 BLE WEBHOOK  (fixed-scanner, event-driven, no pairing timer)
# ============================================================

# RUTX11 scanner registry: { hostname/mac → { lat, lng, name } }
rutx11_scanners: Dict[str, Dict] = {}


def _parse_rutx11_payload(payload: dict) -> tuple:
    """
    Parse RUTX11 BLE JSON payload — handles multiple firmware formats.

    Format A — data_sender collection (named plugin sections):
      { "Streaming_Data": {"name":"RUTX1100XXXX", ...},
        "Bluetooth_Monitor": [{"mac":"7C:D9:F4:07:F9:5C","rssi":-43,...}],
        "GPS_Monitoring": {"latitude":32.31,"longitude":34.93,...} }

    Format B — simple webhook:
      { "host":"RUTX11", "lat":32.31, "lng":34.93,
        "data": [{"mac":"7c:d9:f4:07:f9:5c","rssi":-65}] }

    Returns (scanner_id, scanner_lat, scanner_lng, beacons_list)
    where each beacon = { mac, rssi, name, battery, ... }
    """
    # ── Format A: data_sender collection ──────────────────────────────
    streaming = payload.get("Streaming_Data") or {}
    gps_mon   = payload.get("GPS_Monitoring") or {}

    if streaming or gps_mon:
        # Scanner ID from device name
        scanner_id = (
            streaming.get("name") or
            streaming.get("serial") or
            "RUTX11"
        )

        # GPS from GPS_Monitoring section
        scanner_lat = gps_mon.get("latitude") or gps_mon.get("lat")
        scanner_lng = gps_mon.get("longitude") or gps_mon.get("lon") or gps_mon.get("lng")

        # Bluetooth beacons — key is the input's custom name ("Bluetooth_Monitor")
        # Also try common alternative names for the BLE input
        beacons_raw = (
            payload.get("Bluetooth_Monitor") or
            payload.get("bluetooth_monitor") or
            payload.get("bluetooth") or
            payload.get("BLE_Monitor") or
            []
        )
        # NOTE: Do NOT fall back to generic list search here — it would pick up
        # WiFi_scanner_Monitoring data which also contains mac+signal entries.

    # ── Format B: simple webhook ───────────────────────────────────────
    else:
        scanner_id = (
            payload.get("host") or
            payload.get("hostname") or
            payload.get("scanner") or
            payload.get("device") or
            "RUTX11"
        )
        scanner_lat = payload.get("lat") or payload.get("latitude")
        scanner_lng = payload.get("lng") or payload.get("lon") or payload.get("longitude")
        beacons_raw = (
            payload.get("data") or
            payload.get("sensors") or
            payload.get("beacons") or
            payload.get("devices") or
            payload.get("results") or
            []
        )

    # ── Fall back to registered position if GPS missing ───────────────
    if not scanner_lat and scanner_id in rutx11_scanners:
        scanner_lat = rutx11_scanners[scanner_id].get("lat")
        scanner_lng = rutx11_scanners[scanner_id].get("lng")

    # Normalize GPS to float
    try:
        scanner_lat = float(scanner_lat) if scanner_lat is not None else None
        scanner_lng = float(scanner_lng) if scanner_lng is not None else None
    except (TypeError, ValueError):
        scanner_lat = scanner_lng = None

    # ── Build beacon list ──────────────────────────────────────────────
    beacons = []
    for b in beacons_raw:
        if not isinstance(b, dict):
            continue
        mac = (b.get("mac") or b.get("id") or b.get("address") or "").upper().replace(":", "").lower()
        if len(mac) != 12:
            continue
        beacons.append({
            "mac":     mac,
            "rssi":    b.get("rssi") or b.get("signal") or b.get("RSSI"),
            "name":    b.get("name") or b.get("label") or "",
            "battery": b.get("battery") or b.get("battery_level"),
            "temp":    b.get("temperature") or b.get("temp"),
            "scan_ts": b.get("date_iso_8601") or b.get("timestamp"),
            "raw":     b,
        })

    return scanner_id, scanner_lat, scanner_lng, beacons


@app.route("/api/rutx11", methods=["POST"])
def rutx11_webhook():
    """
    RUTX11 BLE Webhook — receives live beacon detections from the fixed scanner.
    No 60-second pairing timer: if the RUTX11 sees a beacon, it IS there.

    Stores every event to BLE_Scans (historical) and updates BLE_Positions (current).

    Expected JSON (flexible — handles multiple RUTX11 firmware formats):
      { "host": "RUTX11", "lat": 32.123, "lng": 34.456,
        "data": [{ "mac": "7c:d9:f4:07:f9:5c", "rssi": -65, "battery": 80 }] }
    """
    from flask import request
    try:
        payload = request.get_json(force=True)
        if not payload:
            return jsonify({"success": False, "error": "Empty payload"}), 400

        scanner_id, scanner_lat, scanner_lng, beacons = _parse_rutx11_payload(payload)

        if not beacons:
            return jsonify({"success": True, "message": "No beacons in payload", "scanner": scanner_id})

        now = datetime.now()
        updated = []

        with data_lock:
            for b in beacons:
                mac = b["mac"]
                rssi = b["rssi"]
                battery = b["battery"]

                # Look up known beacon definition
                bdef = ble_definitions.get(mac, {})
                beacon_name  = b["name"] or bdef.get("name") or mac
                is_known     = mac in ble_definitions

                # Only update position if we have scanner coordinates
                if scanner_lat is not None and scanner_lng is not None:
                    prev = ble_positions.get(mac, {})
                    ble_positions[mac] = {
                        "mac":          mac,
                        "name":         beacon_name,
                        "category":     bdef.get("category", "Unknown"),
                        "lat":          scanner_lat,
                        "lng":          scanner_lng,
                        "tracker_imei": f"rutx11:{scanner_id}",
                        "tracker_label": scanner_id,
                        "last_update":  now.isoformat(),
                        "last_seen":    now,
                        "is_paired":    True,          # Fixed scanner = always "paired"
                        "pairing_duration": 0,
                        "battery":      battery if battery is not None else prev.get("battery"),
                        "rssi":         rssi,
                        "source":       "rutx11",
                    }

                    # Store to BLE_Positions in DB
                    if DB_ENABLED:
                        try:
                            db_helper.update_ble_position(
                                mac=mac, lat=scanner_lat, lng=scanner_lng,
                                tracker_id=f"rutx11:{scanner_id}",
                                tracker_label=scanner_id,
                                is_paired=True,
                                battery_percent=battery,
                            )
                        except Exception as db_err:
                            logger.warning(f"[RUTX11] DB BLE_Positions error: {db_err}")

                # Always store raw scan event to BLE_Scans (historical log)
                if DB_ENABLED:
                    try:
                        db_helper.log_ble_scan(
                            mac=mac,
                            lat=scanner_lat, lng=scanner_lng,
                            tracker_imei=f"rutx11:{scanner_id}",
                            tracker_label=scanner_id,
                            rssi=rssi,
                            battery_percent=battery,
                            is_known_beacon=is_known,
                        )
                    except Exception as db_err:
                        logger.warning(f"[RUTX11] DB BLE_Scans error: {db_err}")

                updated.append({"mac": mac, "name": beacon_name, "rssi": rssi, "known": is_known})
                logger.info(
                    f"[RUTX11] {beacon_name} ({mac}) rssi={rssi} "
                    f"at scanner={scanner_id} ({scanner_lat},{scanner_lng})"
                )

        return jsonify({
            "success":  True,
            "scanner":  scanner_id,
            "received": len(beacons),
            "updated":  updated,
        })

    except Exception as e:
        logger.error(f"[RUTX11] Webhook error: {e}")
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/rutx11/register", methods=["POST"])
def rutx11_register():
    """
    Register a RUTX11 scanner with its fixed GPS position.
    Call once to tell the broker where the RUTX11 is physically located.

    POST body: { "scanner_id": "RUTX11", "lat": 32.123, "lng": 34.456, "name": "Terminal 3 Gate 5" }
    """
    from flask import request
    try:
        data = request.get_json(force=True)
        scanner_id = data.get("scanner_id") or data.get("host") or data.get("hostname", "RUTX11")
        lat  = float(data["lat"])
        lng  = float(data["lng"])
        name = data.get("name", scanner_id)

        rutx11_scanners[scanner_id] = {"lat": lat, "lng": lng, "name": name}

        # Persist to System_Config so it survives restarts
        if DB_ENABLED:
            try:
                import json as _json
                conn   = db_helper.get_connection()
                cursor = conn.cursor()
                key = f"rutx11_scanner_{scanner_id}"
                val = _json.dumps({"lat": lat, "lng": lng, "name": name})
                cursor.execute("""
                    MERGE System_Config AS target
                    USING (VALUES (?, ?)) AS source (config_key, config_value)
                    ON target.config_key = source.config_key
                    WHEN MATCHED THEN UPDATE SET config_value = source.config_value
                    WHEN NOT MATCHED THEN INSERT (config_key, config_value) VALUES (source.config_key, source.config_value);
                """, key, val)
                conn.commit()
            except Exception as db_err:
                logger.warning(f"[RUTX11] DB register error: {db_err}")

        logger.info(f"[RUTX11] Registered scanner '{scanner_id}' at ({lat}, {lng}) name='{name}'")
        return jsonify({"success": True, "scanner_id": scanner_id, "lat": lat, "lng": lng})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400


@app.get("/api/rutx11/scanners")
def rutx11_list_scanners():
    """List all registered RUTX11 scanners and their positions."""
    return jsonify({"scanners": rutx11_scanners})


# ============================================================
# MAIN
# ============================================================
def main():
    logger.info("=" * 60)
    logger.info("Teltonika Direct Broker Starting")
    logger.info("=" * 60)
    logger.info(f"TCP Port (Devices): {TCP_PORT}")
    logger.info(f"HTTP Port (API): {HTTP_PORT}")
    logger.info(f"Database: {'Enabled' if DB_ENABLED else 'Disabled'}")
    logger.info(f"Known BLE Definitions: {len(ble_definitions)}")
    logger.info("=" * 60)
    
    # Load BLE definitions from database
    if DB_ENABLED:
        try:
            db_defs = db_helper.get_ble_definitions()
            ble_definitions.update(db_defs)
            logger.info(f"[DB] Loaded {len(db_defs)} BLE definitions")
            
            # Load stored BLE positions
            db_positions = db_helper.get_all_ble_positions()
            for mac, pos in db_positions.items():
                if mac not in ble_positions:
                    ble_positions[mac] = {
                        "lat": pos.get("lat"),
                        "lng": pos.get("lng"),
                        "tracker_imei": str(pos.get("last_tracker_id", "")),
                        "tracker_label": pos.get("last_tracker_label", ""),
                        "last_update": pos.get("last_update"),
                        "is_paired": pos.get("is_paired", False),
                        "battery": pos.get("battery_percent"),
                    }
            logger.info(f"[DB] Loaded {len(db_positions)} stored BLE positions")

            # Load persisted RUTX11 scanner registrations
            loaded_scanners = db_helper.get_rutx11_scanners()
            rutx11_scanners.update(loaded_scanners)
            if loaded_scanners:
                for sid, info in loaded_scanners.items():
                    logger.info(f"[DB] Loaded RUTX11 scanner '{sid}' at ({info.get('lat')},{info.get('lng')}) — {info.get('name','')}")
        except Exception as e:
            logger.error(f"[DB] Load error: {e}")
    
    # Start TCP server in background thread
    tcp_thread = threading.Thread(target=tcp_server)
    tcp_thread.daemon = True
    tcp_thread.start()
    
    # Start HTTP server (Flask)
    logger.info(f"[HTTP] API server starting on port {HTTP_PORT}")
    app.run(host="0.0.0.0", port=HTTP_PORT, debug=False, threaded=True)


if __name__ == "__main__":
    main()
