#!/usr/bin/env python3
"""Run beacon seed: BLE_Definitions + BLE_Positions. Uses db_helper connection."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import db_helper

DEFINITIONS = [
    ("7cd9f407f95c", "Eybe2plus1", "Towed Device", "eye_beacon", "6204011070"),
    ("7cd9f4003536", "Eybe2plus2", "Equipment", "eye_beacon", "6204011168"),
    ("7cd9f406427b", "EyeBe3", "Equipment", "eye_beacon", ""),
    ("7cd9f407a2db", "EyeBe4", "Equipment", "eye_beacon", ""),
    ("7cd9f4116ee7", "Eysen2plus", "Safety", "eye_sensor", "6134010143"),
]
POSITIONS = [
    ("7cd9f407f95c", "Eybe2plus1", "Towed Device", "eye_beacon", "6204011070", 32.3119616, 34.9324433, "2026-02-19 14:22:20", 1),
    ("7cd9f4003536", "Eybe2plus2", "Equipment", "eye_beacon", "6204011168", 32.3094883, 34.9303666, "2026-02-19 15:18:10", 1),
    ("7cd9f406427b", "EyeBe3", "Equipment", "eye_beacon", "", 32.308865, 34.93079, "2026-02-19 14:48:23", 1),
    ("7cd9f407a2db", "EyeBe4", "Equipment", "eye_beacon", "", 32.3142616, 34.9349766, "2026-02-19 14:25:19", 1),
    ("7cd9f4116ee7", "Eysen2plus", "Safety", "eye_sensor", "6134010143", 32.310117, 34.932402, "2026-02-19 19:14:37", 0),
]

def main():
    conn = db_helper.get_connection()
    cur = conn.cursor()
    cur.execute("DELETE FROM BLE_Positions")
    cur.execute("DELETE FROM BLE_Definitions")
    for row in DEFINITIONS:
        cur.execute(
            "INSERT INTO BLE_Definitions (mac, name, category, ble_type, serial_number) VALUES (?, ?, ?, ?, ?)",
            row,
        )
    for row in POSITIONS:
        cur.execute(
            """INSERT INTO BLE_Positions (mac, name, category, ble_type, serial_number, lat, lng, last_update, is_paired)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            row,
        )
    conn.commit()
    print("All beacon definitions and positions inserted!")
    cur.execute("SELECT COUNT(*) FROM BLE_Definitions")
    print(f"  BLE_Definitions: {cur.fetchone()[0]} rows")
    cur.execute("SELECT COUNT(*) FROM BLE_Positions")
    print(f"  BLE_Positions:   {cur.fetchone()[0]} rows")
    cur.close()

if __name__ == "__main__":
    main()
