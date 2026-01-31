#!/usr/bin/env python3
"""
Navixy Live Map - Data API Server
Provides /data endpoint for the static map UI.
"""

import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, List

import requests
from flask import Flask, jsonify

API_BASE_URL = os.environ.get("NAVIXY_BASE_URL", "https://api.navixy.com/v2")
API_HASH = os.environ.get("NAVIXY_API_HASH")  # required

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


def _build_row(tracker: Dict[str, Any], state: Dict[str, Any]) -> Dict[str, Any]:
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
        _safe_get(state, "battery", "updated") or _safe_get(state, "battery", "last_update") or last_update_raw
    )
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
        "battery_level": state.get("battery_level"),
        "gps_signal": gps_signal,
        "gsm_signal": gsm_signal,
        "inputs": state.get("inputs"),
        "outputs": state.get("outputs"),
        "sensors_count": state.get("sensors_count"),
        **sensors,
    }
    row.update(
        {
            "movement_status__updated": last_update,
            "connection_status__updated": last_update,
            "battery_level__updated": battery_updated,
            "gsm_signal__updated": gsm_updated,
            "gps_signal__updated": gps_updated,
            "engine_hours__updated": row.get("engine_hours__updated") or last_update,
            "next_service_hours__updated": row.get("next_service_hours__updated") or last_update,
            "lat_lng__updated": gps_updated,
        }
    )
    return row


@app.get("/health")
def health() -> Any:
    return jsonify({"status": "ok"})


@app.get("/data")
def data() -> Any:
    if not API_HASH:
        return jsonify({"success": False, "error": "NAVIXY_API_HASH is not set", "rows": []}), 500

    trackers_resp = _api_call("tracker/list", {})
    if not trackers_resp.get("success"):
        return jsonify(
            {"success": False, "error": trackers_resp.get("status", {}).get("description"), "rows": []}
        ), 502

    rows: List[Dict[str, Any]] = []
    for tracker in trackers_resp.get("list", []):
        tracker_id = tracker.get("id")
        if not tracker_id:
            continue
        state_resp = _api_call("tracker/get_state", {"tracker_id": tracker_id})
        if not state_resp.get("success"):
            continue
        row = _build_row(tracker, state_resp.get("state", {}))
        rows.append(row)
        time.sleep(0.05)

    return jsonify({"success": True, "rows": rows})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")), debug=False)
