"""Quick test script for Navixy API"""
import requests
import json

API_HASH = 'f038d4c96bfc683cdc52337824f7e5f0'
BASE = 'https://api.navixy.com/v2'

print("Testing Navixy API...")
print()

# Get trackers
resp = requests.post(BASE + '/tracker/list', data={'hash': API_HASH}).json()
trackers = resp.get('list', [])
print(f"Found {len(trackers)} trackers:")

for t in trackers:
    tracker_id = t['id']
    label = t['label']
    
    # Get state
    state_resp = requests.post(BASE + '/tracker/get_state', 
        data={'hash': API_HASH, 'tracker_id': tracker_id}).json()
    state = state_resp.get('state', {})
    gps = state.get('gps', {})
    additional = state.get('additional', {})
    
    # Get beacon
    beacon_data = additional.get('ble_beacon_id', {})
    beacon_mac = beacon_data.get('value', '')[-12:] if beacon_data.get('value') else 'none'
    beacon_updated = beacon_data.get('updated', '')
    
    lat = gps.get('location', {}).get('lat', 0)
    lng = gps.get('location', {}).get('lng', 0)
    
    print(f"  - {label}")
    print(f"      GPS: {lat}, {lng}")
    print(f"      Beacon: {beacon_mac}")
    if beacon_updated:
        print(f"      Beacon Updated: {beacon_updated}")
    print()

print("Done!")
