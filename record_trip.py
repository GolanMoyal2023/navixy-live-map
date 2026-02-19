#!/usr/bin/env python3
"""
Trip Recorder - Records all FMC003 and BLE data during a test trip
Usage: python record_trip.py
Press Ctrl+C to stop recording
"""

import json
import time
import requests
from datetime import datetime
import os
import sys

# Force unbuffered output
sys.stdout.reconfigure(line_buffering=True)

# Configuration
BROKER_URL = "http://127.0.0.1:8768"
POLL_INTERVAL = 5  # seconds between polls
OUTPUT_DIR = "D:/New_Recovery/2Plus/navixy-live-map/trip_logs"

def main():
    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Create trip log file with timestamp
    trip_start = datetime.now()
    filename = f"trip_{trip_start.strftime('%Y%m%d_%H%M%S')}.json"
    filepath = os.path.join(OUTPUT_DIR, filename)
    
    print("=" * 60)
    print("[TRIP RECORDER STARTED]")
    print("=" * 60)
    print(f"Recording to: {filepath}")
    print(f"Polling every {POLL_INTERVAL} seconds")
    print("Press Ctrl+C to stop recording")
    print("=" * 60)
    print()
    
    trip_data = {
        "trip_start": trip_start.isoformat(),
        "trip_end": None,
        "records": [],
        "ble_detections": [],
        "summary": {
            "total_records": 0,
            "beacons_detected": set(),
            "distance_traveled": 0,
        }
    }
    
    last_positions = {}
    record_count = 0
    
    try:
        while True:
            try:
                # Get tracker data
                tracker_resp = requests.get(f"{BROKER_URL}/data", timeout=5)
                tracker_data = tracker_resp.json()
                
                # Get BLE positions
                ble_resp = requests.get(f"{BROKER_URL}/ble/positions", timeout=5)
                ble_data = ble_resp.json()
                
                now = datetime.now()
                
                # Record tracker position
                if tracker_data.get("rows"):
                    for row in tracker_data["rows"]:
                        record = {
                            "timestamp": now.isoformat(),
                            "type": "tracker",
                            "imei": row.get("tracker_id"),
                            "label": row.get("label"),
                            "lat": row.get("lat"),
                            "lng": row.get("lng"),
                            "speed": row.get("speed"),
                            "heading": row.get("heading"),
                            "beacons_detected": len(row.get("beacons", [])),
                            "beacon_macs": [b.get("mac") for b in row.get("beacons", [])],
                        }
                        trip_data["records"].append(record)
                        record_count += 1
                        
                        # Track beacons detected
                        for mac in record["beacon_macs"]:
                            if mac:
                                trip_data["summary"]["beacons_detected"].add(mac)
                        
                        print(f"[{now.strftime('%H:%M:%S')}] Tracker: ({row.get('lat'):.6f}, {row.get('lng'):.6f}) | Speed: {row.get('speed', 0)} | Beacons: {record['beacons_detected']}")
                
                # Record BLE position changes
                if ble_data.get("positions"):
                    for mac, pos in ble_data["positions"].items():
                        last_update = pos.get("last_update", "")
                        last_known = last_positions.get(mac, {}).get("last_update", "")
                        
                        if last_update != last_known:
                            # New detection!
                            ble_record = {
                                "timestamp": now.isoformat(),
                                "type": "ble_detection",
                                "mac": mac,
                                "lat": pos.get("lat"),
                                "lng": pos.get("lng"),
                                "battery": pos.get("battery"),
                                "rssi": pos.get("rssi"),
                                "tracker_imei": pos.get("tracker_imei"),
                                "tracker_label": pos.get("tracker_label"),
                                "is_paired": pos.get("is_paired"),
                                "pairing_duration": pos.get("pairing_duration"),
                                "original_last_update": last_update,
                            }
                            trip_data["ble_detections"].append(ble_record)
                            
                            beacon_name = {
                                "7cd9f407f95c": "Eybe2plus1",
                                "7cd9f4003536": "Eybe2plus2", 
                                "7cd9f406427b": "EyeBe3",
                                "7cd9f407a2db": "EyeBe4",
                                "7cd9f4116ee7": "Eysen2plus",
                            }.get(mac.lower(), mac[-4:])
                            
                            print(f"[{now.strftime('%H:%M:%S')}] >> BLE {beacon_name}: Detected! Battery: {pos.get('battery')}% | Paired: {pos.get('is_paired')}")
                        
                        last_positions[mac] = pos
                
                trip_data["summary"]["total_records"] = record_count
                
            except requests.exceptions.RequestException as e:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] WARNING: Connection error: {e}")
            
            time.sleep(POLL_INTERVAL)
            
    except KeyboardInterrupt:
        print()
        print("=" * 60)
        print("[RECORDING STOPPED]")
        print("=" * 60)
    
    # Finalize trip data
    trip_data["trip_end"] = datetime.now().isoformat()
    trip_data["summary"]["beacons_detected"] = list(trip_data["summary"]["beacons_detected"])
    trip_data["summary"]["total_ble_detections"] = len(trip_data["ble_detections"])
    trip_data["summary"]["duration_seconds"] = (datetime.now() - trip_start).total_seconds()
    
    # Save to file
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(trip_data, f, indent=2, default=str)
    
    print()
    print(f"Trip saved to: {filepath}")
    print()
    print("TRIP SUMMARY:")
    print(f"   Duration: {trip_data['summary']['duration_seconds']:.0f} seconds")
    print(f"   Total records: {trip_data['summary']['total_records']}")
    print(f"   BLE detections: {trip_data['summary']['total_ble_detections']}")
    print(f"   Beacons seen: {len(trip_data['summary']['beacons_detected'])}")
    for mac in trip_data['summary']['beacons_detected']:
        beacon_name = {
            "7cd9f407f95c": "Eybe2plus1",
            "7cd9f4003536": "Eybe2plus2", 
            "7cd9f406427b": "EyeBe3",
            "7cd9f407a2db": "EyeBe4",
            "7cd9f4116ee7": "Eysen2plus",
        }.get(mac.lower(), mac)
        print(f"      - {beacon_name} ({mac})")
    print()

if __name__ == "__main__":
    main()
