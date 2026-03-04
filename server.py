#!/usr/bin/env python3
"""
Navixy Live Map - Data API Server
Provides /data endpoint for the static map UI.
Now with SQL Server integration for BLE position persistence.
"""

import math
import os
import time
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List, Optional

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

# ── Robust in-memory pairing state ───────────────────────────────────────────
# Tracks beacon↔tracker pairing across /data polls so we only commit a position
# once we have 60 s of continuous evidence (not just a single snapshot).
#
# Schema per mac key:
#   tracker_id    : int   – which tracker is currently seeing this beacon
#   tracker_label : str
#   first_seen    : datetime – when we first saw this tracker+beacon pair
#   last_seen     : datetime – most recent detection from Navixy
#   lat, lng      : float  – tracker position at last_seen
#   confirmed     : bool   – True once pairing_duration >= PAIRING_CONFIRM_SEC
#   last_db_write : datetime | None – when we last committed to DB
# ─────────────────────────────────────────────────────────────────────────────
_navixy_pairing: Dict[str, Dict[str, Any]] = {}

FRESHNESS_SEC       = 300   # ignore beacons not seen within 5 min
PAIRING_CONFIRM_SEC = 60    # need 60 s continuous detection to trust position
DROP_CONFIRM_SEC    = 10    # tracker stopped 10 s → beacon dropped here
DB_WRITE_INTERVAL   = 120   # throttle DB writes to at most once every 2 min

# ── BLE MAC blacklist ─────────────────────────────────────────────────────────
# MACs to silently ignore — e.g. FMC devices that sense their own BLE chip.
# cb1817761006: LY_GSE_5032 FMC sensing its own BLE advertisement (random MAC).
# Add more here if new self-detected / junk MACs appear.
BLE_MAC_BLACKLIST = {
    "cb1817761006",
}

# ── Auto-drop movement threshold ─────────────────────────────────────────────
# Only auto-drop a beacon when the tracker has moved at least this many metres
# away from where it last saw the beacon.  Prevents false drops when the FMC
# keeps sending heartbeat pings while the car is parked (tracker appears
# "active" but hasn't moved — beacon is still in the car, not truly dropped).
AUTODROP_MOVE_M = 200   # metres the tracker must have moved before we commit a drop


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Return the great-circle distance in metres between two WGS-84 points."""
    R = 6_371_000  # Earth radius in metres
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


app = Flask(__name__)


@app.after_request
def add_cors_headers(response):  # type: ignore[override]
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, ngrok-skip-browser-warning, bypass-tunnel-reminder"
    return response


def _parse_float(val: Any) -> Optional[float]:
    """Parse a float from strings like '1234.56 h' or '5678 km' or plain numbers."""
    if val is None:
        return None
    try:
        return float(str(val).split()[0])
    except (ValueError, IndexError, AttributeError):
        return None


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
            try:
                last_seen_dt = datetime.strptime(last_seen, "%Y-%m-%d %H:%M:%S")
                if datetime.now() - last_seen_dt > timedelta(hours=24):
                    # Skip old beacon data
                    return beacons
            except Exception:
                pass

        # Get beacon battery from virtual sensors
        battery = None
        for vs in readings.get("virtual_sensors", []) or []:
            label = (vs.get("label") or vs.get("name", "")).lower()
            if "eyebecon" in label or "eye beacon" in label or "ble" in label:
                battery = vs.get("value")
                break

        # Fallback: raw voltage from additional fields (Eye Beacons 2.0–3.0V)
        battery_voltage = None
        if battery is None:
            for vol_key in ("ble_beacon_voltage", "ble_voltage"):
                val = additional.get(vol_key, {})
                if isinstance(val, dict) and val.get("value") is not None:
                    try:
                        battery_voltage = float(val["value"])
                        battery = battery_voltage  # use as battery proxy
                    except (TypeError, ValueError):
                        pass
                    break

        # Extract RSSI (signal strength dBm) from additional fields
        rssi = None
        for rssi_key in ("ble_beacon_rssi", "ble_rssi", "ble_beacon_signal"):
            val = additional.get(rssi_key, {})
            if isinstance(val, dict) and val.get("value") is not None:
                try:
                    rssi = float(val["value"])
                except (TypeError, ValueError):
                    pass
                break

        # Extract temperature (°C) — available when beacon uses Sensors packet format
        temperature = None
        for temp_key in ("ble_beacon_temperature", "ble_temperature", "ble_temp"):
            val = additional.get(temp_key, {})
            if isinstance(val, dict) and val.get("value") is not None:
                try:
                    temperature = float(val["value"])
                except (TypeError, ValueError):
                    pass
                break
        if temperature is None:
            for vs in readings.get("virtual_sensors", []) or []:
                lbl = (vs.get("label") or vs.get("name", "")).lower()
                if "temp" in lbl and "ble" in lbl:
                    try:
                        temperature = float(vs["value"])
                    except (TypeError, ValueError):
                        pass
                    break

        # Extract humidity (%) — available when beacon uses Sensors packet format
        humidity = None
        for hum_key in ("ble_beacon_humidity", "ble_humidity"):
            val = additional.get(hum_key, {})
            if isinstance(val, dict) and val.get("value") is not None:
                try:
                    humidity = float(val["value"])
                except (TypeError, ValueError):
                    pass
                break
        if humidity is None:
            for vs in readings.get("virtual_sensors", []) or []:
                lbl = (vs.get("label") or vs.get("name", "")).lower()
                if "humid" in lbl and "ble" in lbl:
                    try:
                        humidity = float(vs["value"])
                    except (TypeError, ValueError):
                        pass
                    break

        # Get magnet sensor states
        magnet_sensors = {}
        for i in range(1, 5):
            key = f"ble_magnet_sensor_{i}"
            if key in additional:
                magnet_sensors[f"magnet_{i}"] = additional[key].get("value")

        beacon = {
            "mac":             beacon_mac,
            "battery":         battery,
            "battery_voltage": battery_voltage,
            "temperature":     temperature,
            "humidity":        humidity,
            "rssi":            rssi,
            "magnet_sensors":  magnet_sensors,
            "last_seen":       last_seen,
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


def _track_beacon_position(
    mac: str,
    beacon: Dict[str, Any],
    tracker_id: int,
    tracker_lbl: str,
    tracker_lat: Any,
    tracker_lng: Any,
    tracker_spd: float,
    ble_definitions: Dict[str, Any],
    now: datetime,
) -> None:
    """
    Robust in-memory pairing tracker.

    Rules:
      • Beacon must be freshly seen (last_seen age < FRESHNESS_SEC).
      • Same tracker must continuously see the beacon for PAIRING_CONFIRM_SEC (60 s)
        before we write the position to DB.
      • While moving (speed > 2 km/h): update position every DB_WRITE_INTERVAL seconds.
      • When stopped (speed < 2 km/h) and pairing_duration >= DROP_CONFIRM_SEC (10 s):
        write a "dropped here" position immediately (but still throttled to DB_WRITE_INTERVAL).
      • If a different tracker starts seeing the beacon the pairing resets.
      • Stale entries (last_seen older than FRESHNESS_SEC) are pruned on each /data call.
    """
    beacon_name = ble_definitions.get(mac, {}).get("name", mac)

    # Parse Navixy last_seen timestamp
    last_seen_str = beacon.get("last_seen")
    if not last_seen_str:
        return
    try:
        last_seen_dt = datetime.strptime(str(last_seen_str)[:19], "%Y-%m-%d %H:%M:%S")
        age_sec = (now - last_seen_dt).total_seconds()
    except Exception:
        return  # unparseable timestamp – skip

    if age_sec > FRESHNESS_SEC:
        return  # stale Navixy reading – don't update pairing

    entry = _navixy_pairing.get(mac)

    if entry is None or entry.get("tracker_id") != tracker_id:
        # New pairing (or tracker changed) – start the 60-second clock
        _navixy_pairing[mac] = {
            "tracker_id":       tracker_id,
            "tracker_label":    tracker_lbl,
            "first_seen":       now,
            "last_seen":        now,
            "lat":              tracker_lat,
            "lng":              tracker_lng,
            "confirmed":        False,
            "last_db_write":    None,
            "last_contact_type": None,   # track transitions to force drop writes
        }
        print(f"[BLE-PAIR] {mac} ({beacon_name}) - new pairing started with {tracker_lbl}")
        return  # wait for next poll to accumulate duration

    # Same tracker – extend the pairing window
    entry["last_seen"] = now
    entry["lat"]       = tracker_lat
    entry["lng"]       = tracker_lng

    pairing_duration = (entry["last_seen"] - entry["first_seen"]).total_seconds()
    is_moving  = tracker_spd > 2
    is_stopped = tracker_spd <= 2

    # Determine contact type label for popup display
    if is_moving and pairing_duration >= PAIRING_CONFIRM_SEC:
        contact_type = "Towing"
    elif is_stopped and pairing_duration >= DROP_CONFIRM_SEC:
        contact_type = "Dropped Here"
    else:
        contact_type = "Pass Nearby"

    # ── Force immediate DB write when car transitions moving → stopped ──────────
    # Without this: a "Towing" write at T=60s sets last_db_write, so a 60-second
    # stop would NOT trigger a "Dropped Here" write (throttled for 120s).
    # Solution: reset the throttle whenever contact_type changes to "Dropped Here".
    prev_contact_type = entry.get("last_contact_type")
    if contact_type == "Dropped Here" and prev_contact_type != "Dropped Here":
        entry["last_db_write"] = None
        print(f"[BLE-PAIR] {mac} ({beacon_name}) - stopped → forcing Dropped Here write")

    # Decide whether to commit position to DB
    should_write = False
    write_reason = ""

    if is_moving and pairing_duration >= PAIRING_CONFIRM_SEC:
        last_write = entry.get("last_db_write")
        if last_write is None or (now - last_write).total_seconds() >= DB_WRITE_INTERVAL:
            should_write = True
            write_reason = f"MOVING {pairing_duration:.0f}s"
            entry["confirmed"] = True

    elif is_stopped and pairing_duration >= DROP_CONFIRM_SEC:
        last_write = entry.get("last_db_write")
        if last_write is None or (now - last_write).total_seconds() >= DB_WRITE_INTERVAL:
            should_write = True
            write_reason = f"DROPPED {pairing_duration:.0f}s"
            entry["confirmed"] = True

    if not should_write or not DB_ENABLED:
        return

    try:
        db_helper.update_ble_position(
            mac=mac,
            lat=float(tracker_lat),
            lng=float(tracker_lng),
            tracker_id=tracker_id,
            tracker_label=tracker_lbl,
            is_paired=is_moving,
            pairing_duration_sec=int(pairing_duration),
            battery_percent=beacon.get("battery"),
            magnet_status=None,
            rssi=beacon.get("rssi"),
            contact_type=contact_type,
            last_seen_navixy=last_seen_str,
        )
        entry["last_db_write"]    = now
        entry["last_contact_type"] = contact_type
        print(
            f"[BLE-TRACK] {mac} ({beacon_name}) -> "
            f"({float(tracker_lat):.5f}, {float(tracker_lng):.5f}) "
            f"{write_reason} [{contact_type}] via {tracker_lbl}"
        )
    except Exception as e:
        print(f"[BLE-TRACK] DB error for {mac}: {e}")


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
def ble_definitions_endpoint() -> Any:
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
            contact_type=data.get("contact_type"),
            log_movement=True,
            old_lat=old_lat,
            old_lng=old_lng
        )

        return jsonify({"success": success})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.get("/ble/pairing_state")
def ble_pairing_state() -> Any:
    """Debug endpoint – show current in-memory pairing state"""
    state = {}
    for mac, entry in _navixy_pairing.items():
        e = dict(entry)
        for k in ("first_seen", "last_seen", "last_db_write"):
            if e.get(k) is not None:
                e[k] = e[k].isoformat()
        state[mac] = e
    return jsonify({"success": True, "pairing_state": state, "count": len(state)})


@app.get("/data")
def data() -> Any:
    if not API_HASH:
        return jsonify({"success": False, "error": "NAVIXY_API_HASH is not set", "rows": []}), 500

    trackers_resp = _api_call("tracker/list", {})
    if not trackers_resp.get("success"):
        return jsonify(
            {"success": False, "error": trackers_resp.get("status", {}).get("description"), "rows": []}
        ), 502

    # Load BLE definitions from database (once per /data call)
    ble_defs: Dict[str, Any] = {}
    if DB_ENABLED:
        try:
            ble_defs = db_helper.get_ble_definitions()
        except Exception:
            pass

    # Snapshot of wall-clock time for this entire /data call
    now = datetime.now()

    # ── Prune stale pairing entries ──────────────────────────────────────────
    # If a confirmed beacon disappears (signal lost), auto-write "Dropped Here"
    # at the last known tracker position. This handles the case where the beacon
    # goes out of BLE range before a stopped-position write could happen.
    #
    # IMPORTANT: Only auto-drop when the TRACKER is still active.
    # If the tracker also went quiet (car parked/off for the night), do NOT write
    # "Dropped Here" — the beacon is still in the parked car, not actually dropped.
    for _mac in list(_navixy_pairing):
        _entry = _navixy_pairing[_mac]
        entry_age = (now - _entry["last_seen"]).total_seconds()
        if entry_age > FRESHNESS_SEC:
            if _entry.get("confirmed") and _entry.get("lat") and _entry.get("lng") and DB_ENABLED:
                # Only auto-drop when the tracker has MOVED AWAY from the beacon.
                # Strategy:
                #   1. Tracker must be recently active (heartbeat seen).
                #   2. Tracker must have moved >= AUTODROP_MOVE_M metres from the
                #      spot where it last saw the beacon.  This prevents false drops
                #      when the FMC sends heartbeat pings while parked — the car
                #      hasn't moved, so the beacon is still in it, not dropped.
                _should_drop = False
                try:
                    _tc = db_helper.get_connection()
                    _tcur = _tc.cursor()
                    _tcur.execute(
                        "SELECT last_update, lat, lng, movement_status FROM Trackers WHERE id = ?",
                        _entry["tracker_id"]
                    )
                    _trow = _tcur.fetchone()
                    if _trow and _trow[0]:
                        _tracker_age = (now - _trow[0]).total_seconds()
                        _tracker_active = _tracker_age < FRESHNESS_SEC
                        if _tracker_active:
                            _tr_lat  = float(_trow[1] or 0)
                            _tr_lng  = float(_trow[2] or 0)
                            _bcn_lat = float(_entry["lat"])
                            _bcn_lng = float(_entry["lng"])
                            if _tr_lat and _tr_lng and _bcn_lat and _bcn_lng:
                                _moved_m = _haversine_m(_bcn_lat, _bcn_lng, _tr_lat, _tr_lng)
                                if _moved_m >= AUTODROP_MOVE_M:
                                    _should_drop = True
                                    print(f"[BLE-AUTO-DROP] {_mac}: tracker moved {_moved_m:.0f}m away → DROP")
                                else:
                                    print(f"[BLE-AUTO-DROP] SKIP {_mac} ({_entry.get('tracker_label','?')}) - tracker only {_moved_m:.0f}m away (parked near beacon)")
                            else:
                                print(f"[BLE-AUTO-DROP] SKIP {_mac} - missing lat/lng for distance check")
                        else:
                            print(f"[BLE-AUTO-DROP] SKIP {_mac} ({_entry.get('tracker_label','?')}) - tracker also quiet (car off)")
                except Exception as _te:
                    print(f"[BLE-AUTO-DROP] tracker-check error for {_mac}: {_te}")

                if _should_drop:
                    try:
                        db_helper.update_ble_position(
                            mac=_mac,
                            lat=float(_entry["lat"]),
                            lng=float(_entry["lng"]),
                            tracker_id=_entry["tracker_id"],
                            tracker_label=_entry["tracker_label"],
                            is_paired=False,
                            contact_type="Dropped Here",
                            last_seen_navixy=_entry["last_seen"].strftime("%Y-%m-%d %H:%M:%S"),
                        )
                        print(f"[BLE-AUTO-DROP] {_mac} → ({float(_entry['lat']):.5f}, {float(_entry['lng']):.5f}) after {entry_age:.0f}s signal loss")
                    except Exception as _e:
                        print(f"[BLE-AUTO-DROP] DB error for {_mac}: {_e}")
            print(f"[BLE-PAIR] {_mac} pairing expired (last seen {entry_age:.0f}s ago)")
            del _navixy_pairing[_mac]

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

        # Store tracker current state + time-series log
        if DB_ENABLED and row.get("lat") and row.get("lng"):
            _t_imei     = row.get("imei")
            _t_conn     = row.get("connection_status")
            _t_move     = row.get("movement_status")
            _t_ign      = row.get("ignition")
            _t_bat      = row.get("battery_level")
            _t_gps_sig  = row.get("gps_signal")
            _t_gsm_sig  = row.get("gsm_signal")
            _t_eng_h    = _parse_float(row.get("engine_hours"))
            _t_odo      = _parse_float(row.get("odometer"))
            try:
                db_helper.update_tracker(
                    tracker_id=tracker_id,
                    label=row.get("label", ""),
                    lat=float(row["lat"]),
                    lng=float(row["lng"]),
                    speed=row.get("speed"),
                    battery_percent=_t_bat,
                    imei=_t_imei,
                    connection_status=_t_conn,
                    movement_status=_t_move,
                    ignition=_t_ign,
                    gps_signal=_t_gps_sig,
                    gsm_signal=_t_gsm_sig,
                    engine_hours=_t_eng_h,
                    odometer=_t_odo,
                )
            except Exception as e:
                print(f"[DB] Error saving tracker {tracker_id}: {e}")
            try:
                db_helper.log_tracker_state(
                    tracker_id=tracker_id,
                    label=row.get("label", ""),
                    imei=_t_imei,
                    lat=float(row["lat"]),
                    lng=float(row["lng"]),
                    speed=row.get("speed"),
                    connection_status=_t_conn,
                    movement_status=_t_move,
                    ignition=_t_ign,
                    battery_level=_t_bat,
                    gps_signal=_t_gps_sig,
                    gsm_signal=_t_gsm_sig,
                    engine_hours=_t_eng_h,
                    odometer=_t_odo,
                )
            except Exception as e:
                print(f"[DB] Error logging tracker state {tracker_id}: {e}")

        # ── Enrich beacons + robust position tracking ─────────────────────
        tracker_lat = row.get("lat")
        tracker_lng = row.get("lng")
        tracker_spd = float(row.get("speed") or 0)
        tracker_lbl = row.get("label", "")

        for beacon in row.get("beacons", []):
            mac = beacon.get("mac", "").lower()

            # Skip blacklisted MACs (e.g. FMC sensing its own BLE chip)
            if mac in BLE_MAC_BLACKLIST:
                print(f"[BLE-SKIP] Blacklisted MAC {mac} ignored")
                continue

            # Enrich beacon with known definition metadata
            if mac and mac in ble_defs:
                beacon.update({
                    "name":       ble_defs[mac].get("name"),
                    "category":   ble_defs[mac].get("category"),
                    "beaconType": ble_defs[mac].get("type"),
                    "sn":         ble_defs[mac].get("sn"),
                })

            # Heartbeat: refresh last_update, battery, RSSI, last_seen on every detection
            # (keeps popup "Last seen at" fresh even for non-paired beacons)
            if mac and DB_ENABLED:
                # Determine live contact_type / pairing duration from in-memory state
                _pairing_entry = _navixy_pairing.get(mac, {})
                _live_contact_type = None
                _live_pairing_dur  = None
                if _pairing_entry:
                    _pdur = (now - _pairing_entry.get("first_seen", now)).total_seconds()
                    _live_pairing_dur = int(_pdur)
                    if tracker_spd > 2 and _pdur >= PAIRING_CONFIRM_SEC:
                        _live_contact_type = "Towing"
                    elif tracker_spd <= 2 and _pdur >= DROP_CONFIRM_SEC:
                        _live_contact_type = "Dropped Here"
                    else:
                        _live_contact_type = "Pass Nearby"
                try:
                    db_helper.update_ble_heartbeat(
                        mac=mac,
                        battery_percent=beacon.get("battery"),
                        battery_voltage=beacon.get("battery_voltage"),
                        temperature=beacon.get("temperature"),
                        humidity=beacon.get("humidity"),
                        rssi=beacon.get("rssi"),
                        last_seen_navixy=beacon.get("last_seen"),
                        tracker_id=tracker_id,
                        tracker_label=tracker_lbl,
                    )
                except Exception:
                    pass
                # Time-series: log every beacon detection to BLE_Scans
                if tracker_lat and tracker_lng:
                    try:
                        db_helper.log_ble_detection(
                            mac=mac,
                            lat=float(tracker_lat),
                            lng=float(tracker_lng),
                            tracker_id=tracker_id,
                            tracker_imei=row.get("imei"),
                            tracker_label=tracker_lbl,
                            rssi=beacon.get("rssi"),
                            battery_percent=beacon.get("battery"),
                            battery_voltage=beacon.get("battery_voltage"),
                            temperature=beacon.get("temperature"),
                            humidity=beacon.get("humidity"),
                            is_known_beacon=(mac in ble_defs),
                            contact_type=_live_contact_type,
                            pairing_duration_sec=_live_pairing_dur,
                        )
                    except Exception:
                        pass

            # Only track position for known beacons on a tracker with valid GPS
            if not (mac and mac in ble_defs and tracker_lat and tracker_lng):
                continue

            _track_beacon_position(
                mac=mac,
                beacon=beacon,
                tracker_id=tracker_id,
                tracker_lbl=tracker_lbl,
                tracker_lat=tracker_lat,
                tracker_lng=tracker_lng,
                tracker_spd=tracker_spd,
                ble_definitions=ble_defs,
                now=now,
            )

        rows.append(row)
        time.sleep(0.05)

    # Add stored BLE positions to response for persistence across page loads
    stored_ble_positions: Dict[str, Any] = {}
    if DB_ENABLED:
        try:
            stored_ble_positions = db_helper.get_all_ble_positions()
        except Exception:
            pass

    # Merge live RSSI / battery / last_seen from this scan into stored positions
    # (so popup shows real-time values even between confirmed position writes)
    for row in rows:
        for beacon in row.get("beacons", []):
            mac_lc = (beacon.get("mac") or "").lower()
            if mac_lc and mac_lc in stored_ble_positions:
                pos = stored_ble_positions[mac_lc]
                if beacon.get("rssi") is not None:
                    pos["rssi"] = beacon["rssi"]
                if beacon.get("battery") is not None:
                    pos["battery"] = beacon["battery"]
                if beacon.get("last_seen"):
                    pos["last_seen"] = beacon["last_seen"]

    return jsonify({
        "success": True,
        "rows": rows,
        "ble_positions": stored_ble_positions,
        "db_enabled": DB_ENABLED
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")), debug=False)
