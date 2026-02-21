#!/usr/bin/env python3
"""
Import BLE positions from your SQL export (CSV) into BLE_Positions.
Use this so the broker has a start point until live data pops in.

Usage:
  python scripts/import_ble_from_csv.py path/to/export.csv

CSV columns (case-insensitive, order doesn't matter). Minimum: mac, lat, lng.
  mac, lat, lng, last_update, battery_percent, last_tracker_label, name, category, ble_type, serial_number

Example CSV header:
  mac,lat,lng,last_update,battery_percent,last_tracker_label,name,category
  7cd9f407f95c,32.311962,34.932443,2026-02-19 14:25:19,85,Direct,Eybe2plus1,Towed Device
"""
import csv
import sys
import os
from datetime import datetime

# Run from repo root so db_helper is importable
_script_dir = os.path.dirname(os.path.abspath(__file__))
_root = os.path.dirname(_script_dir)
if _root not in sys.path:
    sys.path.insert(0, _root)

import db_helper


def _parse_dt(s):
    if not s or str(s).strip() == "":
        return None
    s = str(s).strip()
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d", "%d/%m/%Y %H:%M:%S", "%d/%m/%Y"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def _col(row, *names):
    for n in names:
        for k, v in row.items():
            if k and k.strip().lower() == n.lower():
                return v.strip() if v is not None else ""
    return ""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("Usage: python scripts/import_ble_from_csv.py <path/to/export.csv>")
        sys.exit(1)
    path = sys.argv[1]
    if not os.path.isfile(path):
        print(f"File not found: {path}")
        sys.exit(1)

    rows = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    if not rows:
        print("No rows in CSV.")
        sys.exit(1)

    conn = db_helper.get_connection()
    cursor = conn.cursor()
    updated = 0
    inserted = 0
    errors = []

    for i, row in enumerate(rows):
        mac = _col(row, "mac", "mac_address", "macaddress").lower().replace(":", "").replace("-", "")
        if not mac:
            errors.append(f"Row {i+2}: missing mac")
            continue
        try:
            lat = float(_col(row, "lat", "latitude") or 0)
            lng = float(_col(row, "lng", "lng", "lon", "longitude") or 0)
        except ValueError:
            errors.append(f"Row {i+2} ({mac}): invalid lat/lng")
            continue
        last_update = _parse_dt(_col(row, "last_update", "last_update", "lastupdate", "updated_at"))
        battery_raw = _col(row, "battery_percent", "battery", "battery_percent", "batterypercent")
        battery_percent = None
        if battery_raw != "":
            try:
                battery_percent = int(float(battery_raw))
            except ValueError:
                pass
        last_tracker_label = _col(row, "last_tracker_label", "tracker_label", "tracker", "last_tracker_label") or None
        name = _col(row, "name", "beacon_name") or None
        category = _col(row, "category") or None
        ble_type = _col(row, "ble_type", "type") or "eye_beacon"
        serial_number = _col(row, "serial_number", "sn", "serial") or None

        try:
            cursor.execute("SELECT id FROM BLE_Positions WHERE mac = ?", mac)
            if cursor.fetchone():
                cursor.execute("""
                    UPDATE BLE_Positions
                    SET lat = ?, lng = ?, last_update = COALESCE(?, last_update), battery_percent = COALESCE(?, battery_percent),
                        last_tracker_label = COALESCE(?, last_tracker_label), name = COALESCE(?, name),
                        category = COALESCE(?, category), ble_type = COALESCE(?, ble_type), serial_number = COALESCE(?, serial_number)
                    WHERE mac = ?
                """, lat, lng, last_update, battery_percent, last_tracker_label, name, category, ble_type, serial_number, mac)
                updated += 1
            else:
                cursor.execute("""
                    INSERT INTO BLE_Positions (mac, lat, lng, last_update, battery_percent, last_tracker_label, name, category, ble_type, serial_number)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, mac, lat, lng, last_update, battery_percent, last_tracker_label, name, category, ble_type, serial_number)
                inserted += 1
        except Exception as e:
            errors.append(f"Row {i+2} ({mac}): {e}")

    if errors:
        for e in errors:
            print(f"  Error: {e}")
    conn.commit()
    print(f"Done: {inserted} inserted, {updated} updated.")
    if inserted or updated:
        print("Restart the broker so it loads this data from SQL.")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
