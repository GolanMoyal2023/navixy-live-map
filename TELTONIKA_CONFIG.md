# Teltonika Device Configuration Guide

## Overview

This guide explains how to configure Teltonika FMC650/FMC003 devices to:
1. Send data to both Navixy AND your local broker
2. Detect and report ALL Eye Beacons/Sensors
3. Enable advanced beacon parsing for full BLE data

## Device Support

| Model | GPS | BLE | Max Beacons | Notes |
|-------|-----|-----|-------------|-------|
| FMC650 | ✅ | ✅ | Up to 10 | Recommended for large deployments |
| FMC003 | ✅ | ✅ | Up to 5 | Compact, good for vehicles |

## Known Eye Beacons (2Plus Project)

| MAC Address | Name | Type | Serial |
|-------------|------|------|--------|
| 7CD9F407F95C | Eybe2plus1 | Eye Beacon | 6204011070 |
| 7CD9F4003536 | Eybe2plus2 | Eye Beacon | 6204011168 |
| 7CD9F4116EE7 | Eysen2plus | Eye Sensor | 6134010143 |

## Required Software

- [Teltonika Configurator](https://wiki.teltonika-gps.com/view/Teltonika_Configurator)
- USB cable for device connection

## Configuration Steps

### Step 1: Connect to Device

1. Download and install Teltonika Configurator
2. Connect FMC003/FMC650 via USB
3. Wait for device detection
4. Click "Read configuration"

### Step 2: Configure Server Settings

**GPRS Settings → Server Settings**

#### Primary Server (Navixy - Keep Existing)

| Setting | Value |
|---------|-------|
| Domain | tracker.navixy.com |
| Port | 47776 |
| Protocol | TCP |

#### Second Server Settings (Local Broker via ngrok)

| Setting | Value |
|---------|-------|
| Server Mode | **Duplicate** |
| Domain | 6.tcp.eu.ngrok.io (or your ngrok address) |
| Port | 14669 (or your ngrok port) |
| Protocol | TCP |
| TLS Encryption | None |

```
┌─────────────────────────────────────────────────────────────┐
│  Server Settings (Primary)                                  │
├─────────────────────────────────────────────────────────────┤
│  Domain: tracker.navixy.com                                 │
│  Port:   47776                                              │
│  Protocol: TCP                                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Second Server Settings                                     │
├─────────────────────────────────────────────────────────────┤
│  Server Mode: [Duplicate] ← IMPORTANT!                      │
│  Domain: 6.tcp.eu.ngrok.io                                  │
│  Port:   14669                                              │
│  Protocol: TCP                                              │
│  TLS Encryption: None                                       │
└─────────────────────────────────────────────────────────────┘
```

> **Important:** Set Server Mode to **"Duplicate"** to send ALL data (including beacons) to both servers.

### Step 3: Configure General Bluetooth Settings

**Bluetooth → General Bluetooth Settings**

| Setting | Value |
|---------|-------|
| Bluetooth Radio | **Enable (visible)** |
| Local Name | FMC0032Plus (or your device name) |
| Local PIN | 0000 |
| Security Mode | **None** |

```
┌─────────────────────────────────────────────────────────────┐
│  General Bluetooth Settings                                 │
├─────────────────────────────────────────────────────────────┤
│  Bluetooth Radio: [Enable (visible)] ← Required!           │
│  Local Name: FMC0032Plus                                    │
│  Local PIN: 0000                                            │
│  Security Mode: [None]                                      │
└─────────────────────────────────────────────────────────────┘
```

### Step 4: Configure Beacon Settings

**Bluetooth → Beacon Settings**

| Setting | Value | Notes |
|---------|-------|-------|
| Beacon Detection | **All** | Detect all nearby beacons |
| Beacon Parsing Mode | **Advanced** ⚠️ | **CRITICAL - Must be Advanced!** |
| Beacon Record Saving | **Periodic** | Send at regular intervals |
| Beacon Record Priority | **High Priority** | Ensure beacon data is sent |
| Record Period on Move | 60s | When moving |
| Record Period on Stop | 60s | When stopped |
| Beacon Clear Timeout | 10s | Remove after not seen |

```
┌─────────────────────────────────────────────────────────────┐
│  Beacon Settings                                            │
├─────────────────────────────────────────────────────────────┤
│  Beacon Detection: [All] ← Detects all nearby beacons      │
│                                                             │
│  Beacon Parsing Mode: [Advanced] ← ⚠️ MUST BE ADVANCED!     │
│                                                             │
│  Beacon Record Saving: [Periodic]                           │
│  Beacon Record Priority: [High Priority]                    │
│                                                             │
│  Record Period on Move (s): 60                              │
│  Record Period on Stop (s): 60                              │
│  Beacon Clear Timeout (s): 10                               │
└─────────────────────────────────────────────────────────────┘
```

> ⚠️ **CRITICAL**: If Beacon Parsing Mode is "Simple", element 385 (beacon array) will NOT be sent to the server!

### Step 5: Configure EYE Beacon Settings

**Bluetooth → EYE Beacon Settings**

| Setting | Value | Notes |
|---------|-------|-------|
| Beacon Detection | **All** | Detect all Eye Beacons/Sensors |
| Feature Mode | **Proximity** | Track nearby beacons |
| Record Period on Move | 30s | Faster reporting when moving |
| Record Period on Stop | 30s | Regular reporting when stopped |
| EYE Beacon Clear Timeout | 60s | Keep position after losing signal |
| Identifier | **MAC** | Use MAC address as identifier |
| Battery Data | **Battery Voltage** | Report battery level |

```
┌─────────────────────────────────────────────────────────────┐
│  General EYE Beacon Settings                                │
├─────────────────────────────────────────────────────────────┤
│  Beacon Detection: [All]                                    │
│  Feature Mode: [Proximity]                                  │
│                                                             │
│  Record Period on Move (s): 30                              │
│  Record Period on Stop (s): 30                              │
│  EYE Beacon Clear Timeout (s): 60                           │
│                                                             │
│  Identifier: [MAC] ← Use MAC for tracking                   │
│  Battery Data: [Battery Voltage]                            │
└─────────────────────────────────────────────────────────────┘
```

### Step 6: Verify Beacons Are Visible

Before saving, check the **Beacons** tab in Configurator to verify detection:

**Status → Beacons Tab**

You should see all 3 beacons:

| Type | ID (MAC) | RSSI | Battery Voltage | Temperature |
|------|----------|------|-----------------|-------------|
| Eye Beacon | ...7CD9F4003536 | -41 dBm | 3090 mV | N/A |
| Eye Sensor | ...7CD9F4116EE7 | -52 dBm | 3070 mV | 26°C |
| Eye Beacon | ...7CD9F407F95C | -45 dBm | 2920 mV | N/A |

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Visible Beacons                                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│  Type    │ ID                         │ RSSI     │ Battery   │ Temperature  │
├──────────────────────────────────────────────────────────────────────────────┤
│  🔵      │ ...7CD9F4003536             │ -41 dBm  │ 3090 mV   │ N/A          │
│  🔵      │ ...7CD9F4116EE7             │ -52 dBm  │ 3070 mV   │ 26°C         │
│  🔵      │ ...7CD9F407F95C             │ -45 dBm  │ 2920 mV   │ N/A          │
└──────────────────────────────────────────────────────────────────────────────┘
```

> **Note:** If beacons are NOT visible here, they won't be sent to the server. Check beacon power and range.

### Step 7: Add Known Beacons (Optional)

If you want to filter specific beacons only:

**Bluetooth → Beacon List**

| # | MAC Address |
|---|-------------|
| 1 | 7CD9F407F95C |
| 2 | 7CD9F4003536 |
| 3 | 7CD9F4116EE7 |

> **Recommended:** Keep "Beacon Detection" set to "All" to auto-detect all nearby beacons.

### Step 8: Configure I/O Settings

**I/O → AVL IDs** (if available)

Ensure these IO elements are enabled:

| IO ID | Name | Priority | Server |
|-------|------|----------|--------|
| 385 | BLE Beacons Array | High | All Servers |
| 386-389 | BLE Beacon 1-4 | High | All Servers |
| 548 | EYE Beacon Battery | Low | All Servers |
| 551-554 | EYE Magnet Status | Low | All Servers |

> **Note:** On some firmware versions, IO 385 is automatically included when Beacon Parsing Mode is "Advanced".

### Step 9: Save and Reboot

1. Click **"Save to device"**
2. Click **"Reboot device"** 
3. Wait 30-60 seconds for device to reconnect
4. Device will reconnect to both Navixy and ngrok broker

## Verification

### Check Configurator (Before Saving)

In Teltonika Configurator **Beacons** tab:
- Should show 3 beacons with RSSI and battery voltage
- If empty, check beacon power and range (< 3 meters)

### Check Broker Logs (After Reboot)

```powershell
# Watch broker terminal for beacon data
Get-Content "c:\Users\GolanMoyal\.cursor\projects\d-New-Recovery-2Plus\terminals\34.txt" -Tail 30
```

**Expected Output (SUCCESS):**
```
[TCP] Connection from ('127.0.0.1', 55810)
[TCP] Device authenticated: IMEI 864275078490847
[TCP] 864275078490847: Received 283 bytes
[TCP] 864275078490847 Record 0: IOs=[385, ...], Beacons=3   ← ✅ Beacons!
```

**Current Issue (Beacons=0):**
```
[TCP] 864275078490847 Record 0: IOs=[10828, 10829], Beacons=0  ← ❌ No beacons
```

> ⚠️ If you see `Beacons=0`, change **Beacon Parsing Mode** from "Simple" to **"Advanced"**!

### Check API Endpoint

```powershell
# PowerShell
Invoke-RestMethod "http://127.0.0.1:8768/data" | ConvertTo-Json -Depth 5

# Or Python
cd D:\New_Recovery\2Plus\navixy-live-map
.\.venv\Scripts\python.exe -c "import requests; import json; r = requests.get('http://127.0.0.1:8768/data'); print(json.dumps(r.json(), indent=2))"
```

**Expected Response:**
```json
{
  "success": true,
  "ble_positions": {
    "7cd9f407f95c": { "lat": 32.310, "lng": 34.932, "name": "Eybe2plus1" },
    "7cd9f4003536": { "lat": 32.310, "lng": 34.932, "name": "Eybe2plus2" },
    "7cd9f4116ee7": { "lat": 32.310, "lng": 34.932, "name": "Eysen2plus" }
  }
}
```

## Troubleshooting

### Device Not Connecting

1. Check firewall allows TCP 15027
2. Verify IP address is correct
3. Check device has GPRS/LTE signal

```powershell
# Test port is open
Test-NetConnection -ComputerName localhost -Port 15027
```

### Beacons Not Detected

1. Verify beacons are powered on
2. Check beacons are within range (< 10m)
3. Use Teltonika EYE app to verify beacon is broadcasting
4. Enable "Beacon Detection: All" in configurator

### Only 1 Beacon Showing (Navixy)

This is a Navixy platform limitation. Use the Direct Broker to see ALL beacons.

### Beacon Data is Stale

1. Check "Report Interval" in EYE Beacon Settings
2. Reduce interval to 30 seconds
3. Enable "Beacon on Change"

## Network Requirements

### Inbound (to your PC)

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 15027 | TCP | Teltonika devices | CODEC8 data |

### Outbound (from devices)

| Port | Protocol | Destination | Purpose |
|------|----------|-------------|---------|
| 15027 | TCP | Your PC IP | Broker |
| 12050 | TCP | fm.navixy.com | Navixy |

### Firewall Rule (Windows)

```powershell
# Run as Administrator
New-NetFirewallRule -DisplayName "Teltonika Broker" -Direction Inbound -Protocol TCP -LocalPort 15027 -Action Allow
```

## Best Practices

1. **Use Dual Server** - Send to both Navixy and Broker for redundancy
2. **Set Detection to All** - Don't miss any beacons
3. **Enable Advanced Parsing** - Get battery, temp, humidity data
4. **Short Report Interval** - 30 seconds for real-time tracking
5. **Test with EYE App** - Verify beacons are working before deployment

## Quick Reference

| Setting | Location | Value | Critical? |
|---------|----------|-------|-----------|
| Server Mode | Second Server Settings | **Duplicate** | ⚠️ Yes |
| Server Domain | Second Server Settings | 6.tcp.eu.ngrok.io | ⚠️ Yes |
| Server Port | Second Server Settings | 14669 | ⚠️ Yes |
| Bluetooth Radio | General Bluetooth | Enable (visible) | ⚠️ Yes |
| Beacon Detection | Beacon Settings | **All** | ⚠️ Yes |
| Beacon Parsing Mode | Beacon Settings | **Advanced** | ⚠️⚠️ CRITICAL! |
| Beacon Record Saving | Beacon Settings | Periodic | Yes |
| Beacon Record Priority | Beacon Settings | High Priority | Yes |
| EYE Beacon Detection | EYE Beacon Settings | All | Yes |
| Feature Mode | EYE Beacon Settings | Proximity | Recommended |
| Identifier | EYE Beacon Settings | MAC | Recommended |
| Battery Data | EYE Beacon Settings | Battery Voltage | Recommended |

## Common Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Beacons=0 in logs | Parsing Mode = Simple | Change to **Advanced** |
| Device not connecting | Wrong server address | Check ngrok address/port |
| No beacons in Configurator | Beacons out of range | Place within 3 meters |
| Only 1 beacon showing (Navixy) | Navixy limitation | Use Direct Broker instead |
| Stale beacon positions | Report period too long | Reduce to 30 seconds |
