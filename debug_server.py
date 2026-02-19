"""Debug script to test the server data endpoint"""
import os
import sys

# Set environment BEFORE importing server
os.environ['NAVIXY_API_HASH'] = 'f038d4c96bfc683cdc52337824f7e5f0'

import server

print("API_HASH:", server.API_HASH)
print()

# Test with Flask test client
with server.app.test_client() as client:
    print("Calling /data endpoint...")
    response = client.get('/data')
    print("Status:", response.status_code)
    
    data = response.get_json()
    print("Success:", data.get('success'))
    print("Rows:", len(data.get('rows', [])))
    
    if data.get('error'):
        print("Error:", data.get('error'))
    
    if data.get('rows'):
        for row in data['rows']:
            label = row.get('label')
            lat = row.get('lat')
            lng = row.get('lng')
            beacons = row.get('beacons', [])
            print(f"  - {label}: ({lat}, {lng}) - {len(beacons)} beacons")
            for b in beacons:
                print(f"      Beacon: {b.get('mac')}")
