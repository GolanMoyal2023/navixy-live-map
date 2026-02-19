#!/usr/bin/env python3
"""
Navixy Live Map - Data API Server
Provides /data endpoint for the static map UI.
Now with SQL Server integration for BLE position persistence.
"""

import os
import time
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List

import requests
from flask import Flask, jsonify, send_from_directory, request

# Import database helper
try:
    import db_helper
    DB_ENABLED = True
    print("[DB] SQL Server integration enabled")
except Exception as e:
    DB_ENABLED = False
    print(f"[DB] SQL Server integration disabled: {e}")

API_BASE_URL = os.environ.get("NAVIXY_BASE_URL", "https://api.navixy.com/v2")
# API hash - use environment variable or fallback to default for development
API_HASH = os.environ.get("NAVIXY_API_HASH") or "f038d4c96bfc683cdc52337824f7e5f0"

POLL_TIMEOUT_SECONDS = int(os.environ.get("NAVIXY_TIMEOUT", "10"))

app = Flask(__name__)


@app.after_request
def add_cors_headers(response):  # type: ignore[override]
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    return response


def _api_call(endpoint: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    url = f"{API_BASE_URL}/{endpoint}"
    data = dict(payload)
    data["hash"] = API_HASH
    response = requests.post(url, data=data, timeout=POLL_TIMEOUT_SECONDS)
    response.raise_for_status()
    return response.json()


def _safe_get(state: Dict[str, Any], *keys: str) -> Any:
    value: Any = state
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def _format_timestamp(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc).isoformat()
    return str(value)


def _format_sensor_value(value: Any, units: Any) -> Any:
    if units and value is not None:
        return f"{value} {units}"
    return value


def _format_number(value: Any, *, force_decimals: bool = False) -> Any:
    raw = value
    if isinstance(value, str):
        try:
            value = float(value)
        except ValueError:
            return raw
    if not isinstance(value, (int, float)):
        return raw
    if force_decimals:
        return f"{value:.2f}"
    if abs(value - int(value)) < 1e-9:
        return str(int(value))
    return f"{value:.2f}"


def _strip_custom_suffix(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    return value.replace(" custom", "")


def _normalize_units(units: Any, units_type: Any) -> Any:
    if units:
        return units
    if not units_type:
        return None
    units_type_text = str(units_type).lower()
    if units_type_text == "custom":
        return None
    unit_map = {
        "volt": "V",
        "percent": "%",
        "hour": "h",
        "hours": "h",
        "kilometer": "km",
        "kilometre": "km",
    }
    return unit_map.get(units_type_text, units_type)


def _extract_sensors(state: Dict[str, Any]) -> Dict[str, Any]:
    sensors: Dict[str, Any] = {}
    if not isinstance(state, dict):
        return sensors
    for item in state.get("sensors", []) or []:
        if not isinstance(item, dict):
            continue
        label = item.get("label") or item.get("name")
        if not label:
            continue
        value = _format_sensor_value(item.get("value"), item.get("units"))
        sensors[label] = value
        sensors[f"{label}__updated"] = _format_timestamp(item.get("updated"))
    return sensors


def _extract_readings(readings: Dict[str, Any]) -> Dict[str, Any]:
    data: Dict[str, Any] = {}
    if not isinstance(readings, dict):
        return data
    for item in readings.get("inputs", []) or []:
        if not isinstance(item, dict):
            continue
        label = item.get("label") or item.get("name")
        if not label:
            continue
        units = _normalize_units(item.get("units"), item.get("units_type"))
        raw_value = item.get("value")
        force_decimals = label in {"engine_hours_total"}
        value = _format_sensor_value(_format_number(raw_value, force_decimals=force_decimals), units)
        value = _strip_custom_suffix(value)
        data[label] = value
        data[f"{label}__updated"] = _format_timestamp(item.get("update_time"))
    for item in readings.get("virtual_sensors", []) or []:
        if not isinstance(item, dict):
            continue
        label = item.get("label") or item.get("name")
        if not label:
            continue
        data[label] = _strip_custom_suffix(item.get("value"))
        data[f"{label}__updated"] = _format_timestamp(item.get("update_time"))
    for item in readings.get("counters", []) or []:
        if not isinstance(item, dict):
            continue
        counter_type = item.get("type")
        if not counter_type:
            continue
        raw_value = item.get("value")
        if counter_type == "engine_hours":
            value = _format_sensor_value(_format_number(raw_value, force_decimals=True), "h")
        elif counter_type == "odometer":
            value = _format_sensor_value(_format_number(raw_value), "km")
        else:
            value = _format_number(raw_value)
        value = _strip_custom_suffix(value)
        data[counter_type] = value
        data[f"{counter_type}__updated"] = _format_timestamp(item.get("update_time"))
    return data


def _extract_beacons(state: Dict[str, Any], readings: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Extract Eye Beacon/Sensor data from tracker state"""
    beacons = []
    additional = state.get("additional", {}) if isinstance(state, dict) else {}
    
    # Check for BLE beacon data
    ble_beacon_id = additional.get("ble_beacon_id", {}).get("value")
    hardware_key = additional.get("hardware_key", {}).get("value")
    
    # Get the MAC address (last 12 chars of the full ID)
    beacon_mac = None
    if ble_beacon_id:
        beacon_mac = ble_beacon_id[-12:].upper() if len(ble_beacon_id) >= 12 else ble_beacon_id.upper()
    elif hardware_key:
        beacon_mac = hardware_key[-12:].upper() if len(hardware_key) >= 12 else hardware_key.upper()
    
    if beacon_mac:
        # Get last seen timestamp
        last_seen = additional.get("ble_beacon_id", {}).get("updated") or additional.get("hardware_key", {}).get("updated")
        
        # Filter out old beacon data (more than 24 hours old)
        if last_seen:
            from datetime import datetime, timedelta
            try:
                last_seen_dt = datetime.strptime(last_seen, "%Y-%m-%d %H:%M:%S")
                if datetime.now() - last_seen_dt > timedelta(hours=24):
                    # Skip old beacon data
                    return beacons
            except:
                pass
        
        # Get beacon battery from virtual sensors
        battery = None
        for vs in readings.get("virtual_sensors", []) or []:
            label = (vs.get("label") or vs.get("name", "")).lower()
            if "eyebecon" in label or "eye beacon" in label or "ble" in label:
                battery = vs.get("value")
                break
        
        # Get magnet sensor states
        magnet_sensors = {}
        for i in range(1, 5):
            key = f"ble_magnet_sensor_{i}"
            if key in additional:
                magnet_sensors[f"magnet_{i}"] = additional[key].get("value")
        
        beacon = {
            "mac": beacon_mac,
            "battery": battery,
            "magnet_sensors": magnet_sensors,
            "last_seen": last_seen,
        }
        beacons.append(beacon)
    
    return beacons


def _build_row(tracker: Dict[str, Any], state: Dict[str, Any], readings: Dict[str, Any]) -> Dict[str, Any]:
    gps = state.get("gps", {}) if isinstance(state, dict) else {}
    lat = _safe_get(state, "gps", "location", "lat")
    lng = _safe_get(state, "gps", "location", "lng")
    sensors = _extract_sensors(state)
    gps_signal = _safe_get(state, "gps", "signal_level")
    gsm_signal = (
        _safe_get(state, "gsm", "signal_level")
        if _safe_get(state, "gsm", "signal_level") is not None
        else _safe_get(state, "gsm", "level")
    )
    last_update_raw = state.get("last_update") if isinstance(state, dict) else None
    last_update = _format_timestamp(last_update_raw)
    gps_updated = _format_timestamp(gps.get("updated"))
    gsm_updated = _format_timestamp(_safe_get(state, "gsm", "updated") or _safe_get(state, "gsm", "last_update"))
    battery_updated = _format_timestamp(
        _safe_get(state, "battery_update")
        or _safe_get(state, "battery", "updated")
        or _safe_get(state, "battery", "last_update")
        or last_update_raw
    )
    movement_updated = _format_timestamp(
        _safe_get(state, "movement_status_update") or _safe_get(state, "movement_status_updated") or last_update_raw
    )
    ignition_updated = _format_timestamp(_safe_get(state, "ignition_update") or last_update_raw)
    lat_lng = f"{lat} ; {lng}" if lat is not None and lng is not None else None

    row = {
        "tracker_id": tracker.get("id"),
        "label": tracker.get("label"),
        "imei": tracker.get("source", {}).get("device_id"),
        "group_name": tracker.get("group", {}).get("title"),
        "connection_status": state.get("connection_status") if isinstance(state, dict) else None,
        "movement_status": state.get("movement_status") if isinstance(state, dict) else None,
        "last_update": last_update,
        "gps_updated": gps_updated,
        "lat": lat,
        "lng": lng,
        "lat_lng": lat_lng,
        "speed": gps.get("speed"),
        "engine_rpm": state.get("engine_rpm"),
        "engine_hours": state.get("engine_hours"),
        "odometer": state.get("odometer"),
        "ignition": state.get("ignition"),
        "Ignition": state.get("ignition"),
        "battery_level": state.get("battery_level"),
        "gps_signal": gps_signal,
        "gsm_signal": gsm_signal,
        "inputs": state.get("inputs"),
        "outputs": state.get("outputs"),
        "sensors_count": state.get("sensors_count"),
        **sensors,
    }
    row.update(_extract_readings(readings))
    row.update(
        {
            "movement_status__updated": movement_updated,
            "connection_status__updated": last_update,
            "battery_level__updated": battery_updated,
            "gsm_signal__updated": gsm_updated,
            "gps_signal__updated": gps_updated,
            "engine_hours__updated": row.get("engine_hours__updated") or last_update,
            "next_service_hours__updated": row.get("next_service_hours__updated") or last_update,
            "lat_lng__updated": gps_updated,
            "Ignition__updated": ignition_updated,
        }
    )
    
    # Add beacon data
    beacons = _extract_beacons(state, readings)
    row["beacons"] = beacons
    
    return row


@app.get("/")
def index() -> Any:
    """Serve the main map page"""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    return send_from_directory(base_dir, "index.html")


@app.get("/<path:filename>")
def static_files(filename: str) -> Any:
    """Serve static files (geojson, etc.)"""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    return send_from_directory(base_dir, filename)


@app.get("/health")
def health() -> Any:
    return jsonify({"status": "ok", "db_enabled": DB_ENABLED})


@app.get("/ble/positions")
def ble_positions() -> Any:
    """Get all BLE positions from database"""
    if not DB_ENABLED:
        return jsonify({"success": False, "error": "Database not available", "positions": {}})
    
    try:
        positions = db_helper.get_all_ble_positions()
        return jsonify({"success": True, "positions": positions, "count": len(positions)})
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "positions": {}})


@app.get("/ble/definitions")
def ble_definitions() -> Any:
    """Get all BLE definitions from database"""
    if not DB_ENABLED:
        return jsonify({"success": False, "error": "Database not available", "definitions": {}})
    
    try:
        definitions = db_helper.get_ble_definitions()
        return jsonify({"success": True, "definitions": definitions, "count": len(definitions)})
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "definitions": {}})


@app.route("/ble/position", methods=["POST", "OPTIONS"])
def update_ble_position() -> Any:
    """Update BLE position (called by client when pairing confirmed)"""
    if request.method == "OPTIONS":
        return "", 200
    
    if not DB_ENABLED:
        return jsonify({"success": False, "error": "Database not available"})
    
    data = request.get_json()
    
    if not data:
        return jsonify({"success": False, "error": "No data provided"})
    
    mac = data.get("mac", "").lower()
    if not mac:
        return jsonify({"success": False, "error": "MAC address required"})
    
    try:
        # Get old position for movement logging
        old_pos = db_helper.get_ble_position(mac)
        old_lat = old_pos["lat"] if old_pos else None
        old_lng = old_pos["lng"] if old_pos else None
        
        pairing_start = None
        if data.get("pairing_start"):
            pairing_start = datetime.fromisoformat(data["pairing_start"])
        
        success = db_helper.update_ble_position(
            mac=mac,
            lat=float(data.get("lat", 0)),
            lng=float(data.get("lng", 0)),
            tracker_id=int(data.get("tracker_id", 0)),
            tracker_label=data.get("tracker_label", ""),
            is_paired=data.get("is_paired", False),
            pairing_start=pairing_start,
            pairing_duration_sec=int(data.get("pairing_duration_sec", 0)),
            battery_percent=data.get("battery_percent"),
            magnet_status=data.get("magnet_status"),
            log_movement=True,
            old_lat=old_lat,
            old_lng=old_lng
        )
        
        return jsonify({"success": success})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.get("/data")
def data() -> Any:
    if not API_HASH:
        return jsonify({"success": False, "error": "NAVIXY_API_HASH is not set", "rows": []}), 500

    trackers_resp = _api_call("tracker/list", {})
    if not trackers_resp.get("success"):
        return jsonify(
            {"success": False, "error": trackers_resp.get("status", {}).get("description"), "rows": []}
        ), 502

    # Load BLE definitions from database
    ble_definitions = {}
    if DB_ENABLED:
        try:
            ble_definitions = db_helper.get_ble_definitions()
        except:
            pass

    rows: List[Dict[str, Any]] = []
    for tracker in trackers_resp.get("list", []):
        tracker_id = tracker.get("id")
        if not tracker_id:
            continue
        state_resp = _api_call("tracker/get_state", {"tracker_id": tracker_id})
        if not state_resp.get("success"):
            continue
        readings_resp = _api_call("tracker/readings/list", {"tracker_id": tracker_id})
        readings = readings_resp if readings_resp.get("success") else {}
        row = _build_row(tracker, state_resp.get("state", {}), readings)
        
        # Store tracker position in database
        if DB_ENABLED and row.get("lat") and row.get("lng"):
            try:
                db_helper.update_tracker(
                    tracker_id=tracker_id,
                    label=row.get("label", ""),
                    lat=float(row["lat"]),
                    lng=float(row["lng"]),
                    speed=row.get("speed"),
                    battery_percent=row.get("battery_level")
                )
            except Exception as e:
                print(f"[DB] Error saving tracker {tracker_id}: {e}")
        
        # Enrich beacon data with database info and store positions
        for beacon in row.get("beacons", []):
            mac = beacon.get("mac", "").lower()
            if mac and mac in ble_definitions:
                beacon.update({
                    "name": ble_definitions[mac].get("name"),
                    "category": ble_definitions[mac].get("category"),
                    "beaconType": ble_definitions[mac].get("type"),
                    "sn": ble_definitions[mac].get("sn"),
                })
            
            # Note: BLE position storage is handled by the client-side 60-second pairing logic
            # The server just provides the current detection data
        
        rows.append(row)
        time.sleep(0.05)

    # Add stored BLE positions to response for persistence across page loads
    stored_ble_positions = {}
    if DB_ENABLED:
        try:
            stored_ble_positions = db_helper.get_all_ble_positions()
        except:
            pass

    return jsonify({
        "success": True, 
        "rows": rows,
        "ble_positions": stored_ble_positions,
        "db_enabled": DB_ENABLED
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")), debug=False)
