# BLE Asset Tracking - Business Logic

## Overview

This document describes the business logic for tracking BLE-tagged static equipment (tow bars, loaders, etc.) using Teltonika GPS trackers and Eye Beacons.

## The Problem

**Static equipment (tow bars, cargo loaders) don't have GPS.** They are towed/moved by motorized GSE vehicles.

**Solution:** Attach BLE beacons to static equipment. When a GPS tracker (on a tractor) detects the beacon, the equipment "inherits" the tracker's location.

## Key Concepts

### 1. Asset Types

| Type | Example | Has GPS | Has BLE | Movement |
|------|---------|---------|---------|----------|
| **GSE Tracker** | Tractor, Tug | ✅ Yes | Reads BLE | Self-propelled |
| **BLE Asset** | Tow bar, Loader | ❌ No | ✅ Beacon | Towed/Static |

### 2. The Pairing Problem

**Problem:** A tracker might briefly detect a beacon while passing by, but this doesn't mean the equipment moved.

**Example:**
```
08:30 - Tractor passes by a parked tow bar → Detects beacon for 5 seconds
        ❌ Tow bar should NOT move to tractor's position

08:35 - Tractor hooks up tow bar → Detects beacon continuously
08:36 - Still detecting... (60 seconds elapsed)
        ✅ NOW tow bar should inherit tractor's position
```

### 3. The 60-Second Pairing Rule

> **A BLE asset only updates its position when it has been continuously detected by the SAME tracker for more than 60 seconds.**

This ensures:
- Brief pass-by detections are ignored
- Only actual towing/movement updates the position
- Equipment stays at its last known position until moved

## State Machine

```
┌─────────────────────────────────────────────────────────────────┐
│                    BLE POSITION STATE MACHINE                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐                                              │
│   │   UNKNOWN    │  First detection                             │
│   │   (No data)  │────────────────────┐                         │
│   └──────────────┘                    │                         │
│                                       ▼                         │
│                              ┌──────────────┐                   │
│                              │   DETECTED   │                   │
│         Different tracker    │   < 60 sec   │                   │
│         detected             │              │                   │
│   ┌──────────────────────────│  Pairing...  │                   │
│   │                          └──────┬───────┘                   │
│   │                                 │                           │
│   │                    Same tracker │ 60+ seconds               │
│   │                                 ▼                           │
│   │                          ┌──────────────┐                   │
│   │                          │    PAIRED    │                   │
│   └─────────────────────────►│   > 60 sec   │                   │
│                              │              │                   │
│                              │  Following   │                   │
│                              │  Tracker     │                   │
│                              └──────┬───────┘                   │
│                                     │                           │
│                        No detection │ (dropped off)             │
│                                     ▼                           │
│                              ┌──────────────┐                   │
│                              │    STATIC    │                   │
│                              │              │                   │
│                              │  Last known  │                   │
│                              │  position    │                   │
│                              └──────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Pairing Logic (Pseudocode)

```python
def process_beacon(tracker_id, tracker_lat, tracker_lng, beacon_mac):
    now = current_time()
    
    # Check if this is a new pairing or continuing
    current_pairing = get_pairing(beacon_mac)
    
    if current_pairing is None or current_pairing.tracker_id != tracker_id:
        # New tracker detecting this BLE - START pairing timer
        start_pairing(beacon_mac, tracker_id, now)
        log(f"BLE {beacon_mac}: New detection by {tracker_id}, starting 60s timer")
        return  # Don't update position yet
    
    # Same tracker continuing to detect - check duration
    pairing_duration = now - current_pairing.start_time
    
    if pairing_duration >= 60 seconds:
        # PAIRED! BLE is being towed - update position
        old_position = get_ble_position(beacon_mac)
        
        if position_changed(old_position, tracker_lat, tracker_lng):
            update_ble_position(beacon_mac, tracker_lat, tracker_lng)
            log_movement(beacon_mac, old_position, new_position, tracker_id)
            log(f"BLE {beacon_mac}: Paired > 60s, position updated")
    else:
        # Still pairing, waiting for 60 seconds
        log(f"BLE {beacon_mac}: Pairing {pairing_duration}s / 60s")
```

## Scenarios

### Scenario 1: Tractor Passes By (No Update)

```
Time    Action                              BLE Position
─────   ─────────────────────────────────   ─────────────
08:30   Tractor A detects Tow Bar           32.100, 34.200 (unchanged)
08:30   Pairing started with Tractor A      32.100, 34.200 (unchanged)
08:30   Tractor A moves away (10 sec)       32.100, 34.200 (unchanged)
08:30   Detection lost                      32.100, 34.200 (stays at last known)
```

**Result:** Tow bar stays at its original position.

### Scenario 2: Tractor Tows Equipment (Position Updated)

```
Time    Action                              BLE Position
─────   ─────────────────────────────────   ─────────────
08:35   Tractor B hooks up Tow Bar          32.100, 34.200 (unchanged)
08:35   Pairing started with Tractor B      32.100, 34.200 (unchanged)
08:36   Still detecting... (60 seconds)     32.100, 34.200 (unchanged)
08:36   PAIRED! Position updates            32.150, 34.250 (updated!)
08:40   Tractor B at new location           32.200, 34.300 (updated!)
08:45   Tractor B drops off Tow Bar         32.200, 34.300 (stays)
08:45   Detection lost                      32.200, 34.300 (last known)
```

**Result:** Tow bar moved to new location.

### Scenario 3: Different Tractor Picks Up (Pairing Reset)

```
Time    Action                              BLE Position
─────   ─────────────────────────────────   ─────────────
09:00   Tow Bar at 32.200, 34.300           32.200, 34.300
09:05   Tractor C hooks up Tow Bar          32.200, 34.300 (unchanged)
09:05   NEW pairing started with Tractor C  32.200, 34.300 (unchanged)
09:06   Still detecting... (60 seconds)     32.200, 34.300 (unchanged)
09:06   PAIRED! Position updates            32.250, 34.350 (updated!)
```

**Result:** Tow bar now follows Tractor C.

## Data Persistence

### In-Memory (Runtime)
- Current tracker positions
- Active pairings (MAC → tracker_id, start_time)
- BLE positions

### SQL Server (Persistent)
- BLE_Positions: Current positions (survives restart)
- BLE_Movement_Log: History of position changes
- BLE_Pairing_History: Completed pairing sessions

## Map Display

### BLE Status Indicators

| Status | Icon | Color | Description |
|--------|------|-------|-------------|
| **PAIRED** | 🔗 | Green | Following tracker (> 60s) |
| **PAIRING** | ⏳ | Orange | Detecting (< 60s) |
| **STATIC** | 📍 | Gray | Last known position |

### BLE Categories & Shapes

| Category | Shape | Color | Icon |
|----------|-------|-------|------|
| Towed Device | Diamond ◆ | Purple | TowBar.png |
| Equipment | Square ■ | Blue | - |
| Safety | Triangle ▲ | Green | - |
| Container | Pentagon ⬠ | Orange | - |
| Personnel | Circle ● | Red | - |
| Vehicle | Hexagon ⬡ | Violet | - |

### Popup Information

```
┌─────────────────────────────────────┐
│  ◆ Eybe2plus1                       │
│  Category: Towed Device             │
├─────────────────────────────────────┤
│  MAC: f008d1d55c3c                  │
│  S/N: 6204011070                    │
│  Battery: 85%                       │
├─────────────────────────────────────┤
│  📍 BLE Position Info               │
│  Last set by: SKODA                 │
│  Position set: 2026-02-18 09:30:15  │
│  🔗 PAIRED (125s) - Following       │
│  📏 Distance to tracker: 0 m        │
└─────────────────────────────────────┘
```

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| PAIRING_THRESHOLD_SECONDS | 60 | Seconds to confirm pairing |
| POSITION_CHANGE_THRESHOLD | 10 | Meters movement to update |
| BLE_STALE_DAYS | 7 | Days to keep position |
| REFRESH_INTERVAL_MS | 5000 | Map refresh interval |

## Summary

1. **BLE beacons are on STATIC equipment** (no GPS)
2. **Trackers are on MOTORIZED vehicles** (have GPS)
3. **Brief detection (< 60s) = pass-by** → Position unchanged
4. **Sustained detection (> 60s) = towing** → Position updated
5. **Detection lost = dropped off** → Position stays at last known
6. **New tracker = new pairing** → Timer resets
