"""
Teltonika Direct TCP Server
============================
Receives raw CODEC8/CODEC8E data directly from Teltonika FMC devices.
Extracts ALL beacon data (not limited like Navixy).

Port: 5027 (configurable)
Protocol: Teltonika CODEC8 Extended

Author: Navixy Live Map Project
"""

import socket
import struct
import threading
import json
import os
from datetime import datetime, timezone
from flask import Flask, jsonify
from flask_cors import CORS
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration
TCP_PORT = int(os.environ.get("TELTONIKA_TCP_PORT", 15027))  # Higher port to avoid permission issues
API_PORT = int(os.environ.get("TELTONIKA_API_PORT", 8768))
BIND_ADDRESS = "0.0.0.0"

# Storage for device data (in-memory)
device_data = {}
device_data_lock = threading.Lock()

# Known IMEI to tracker name mapping
KNOWN_DEVICES = {
    "864275078490847": {"name": "SKODA", "tracker_id": 3475504},
    # Add more devices as needed
}

# Known beacon MAC to info mapping
KNOWN_BEACONS = {
    "7CD9F407F95C": {"name": "Eybe2plus1", "category": "Towed Device", "sn": "1150232331"},
    "7CD9F4003536": {"name": "Eybe2plus2", "category": "Equipment", "sn": "1149652498"},
    "7CD9F4116EE7": {"name": "Eysen2plus", "category": "Safety", "sn": "1149846140"},
}

# ============================================================================
# CODEC8 PARSER
# ============================================================================

class TeltonikaParser:
    """Parser for Teltonika CODEC8 and CODEC8 Extended protocols"""
    
    # IO element IDs for Eye Beacon/Sensor data
    IO_BEACON_IDS = {
        385: "ble_beacon_1",
        386: "ble_beacon_2", 
        387: "ble_beacon_3",
        388: "ble_beacon_4",
        # Eye Sensor specific
        463: "eye_sensor_battery_1",
        464: "eye_sensor_battery_2",
        465: "eye_sensor_battery_3",
        466: "eye_sensor_battery_4",
        467: "eye_sensor_temperature_1",
        468: "eye_sensor_temperature_2",
        469: "eye_sensor_temperature_3",
        470: "eye_sensor_temperature_4",
        471: "eye_sensor_humidity_1",
        472: "eye_sensor_humidity_2",
        473: "eye_sensor_humidity_3",
        474: "eye_sensor_humidity_4",
        # Magnet sensors
        331: "ble_magnet_sensor_1",
        332: "ble_magnet_sensor_2",
        333: "ble_magnet_sensor_3",
        334: "ble_magnet_sensor_4",
        # BLE Low Energy beacons
        25: "ble_sensor_1_battery",
        26: "ble_sensor_2_battery",
        27: "ble_sensor_3_battery",
        28: "ble_sensor_4_battery",
    }
    
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0
        
    def read_bytes(self, n: int) -> bytes:
        result = self.data[self.pos:self.pos + n]
        self.pos += n
        return result
    
    def read_uint8(self) -> int:
        return struct.unpack(">B", self.read_bytes(1))[0]
    
    def read_uint16(self) -> int:
        return struct.unpack(">H", self.read_bytes(2))[0]
    
    def read_uint32(self) -> int:
        return struct.unpack(">I", self.read_bytes(4))[0]
    
    def read_uint64(self) -> int:
        return struct.unpack(">Q", self.read_bytes(8))[0]
    
    def read_int32(self) -> int:
        return struct.unpack(">i", self.read_bytes(4))[0]
    
    def read_int16(self) -> int:
        return struct.unpack(">h", self.read_bytes(2))[0]

    def parse_avl_data(self) -> dict:
        """Parse AVL data packet (after IMEI handshake)"""
        try:
            # Preamble (4 bytes of zeros)
            preamble = self.read_uint32()
            if preamble != 0:
                logger.warning(f"Invalid preamble: {preamble}")
                return None
            
            # Data field length
            data_length = self.read_uint32()
            
            # Codec ID
            codec_id = self.read_uint8()
            logger.info(f"Codec ID: {codec_id} (0x{codec_id:02X})")
            
            if codec_id not in [0x08, 0x8E]:  # CODEC8 or CODEC8E
                logger.warning(f"Unsupported codec: {codec_id}")
                return None
            
            # Number of records
            num_records = self.read_uint8()
            logger.info(f"Number of records: {num_records}")
            
            records = []
            for i in range(num_records):
                record = self.parse_avl_record(codec_id)
                if record:
                    records.append(record)
            
            # Number of records (again, for verification)
            num_records_end = self.read_uint8()
            
            # CRC
            crc = self.read_uint32()
            
            return {
                "codec": codec_id,
                "records": records,
                "num_records": num_records,
            }
            
        except Exception as e:
            logger.error(f"Error parsing AVL data: {e}")
            return None
    
    def parse_avl_record(self, codec_id: int) -> dict:
        """Parse a single AVL record"""
        try:
            # Timestamp (milliseconds since epoch)
            timestamp_ms = self.read_uint64()
            timestamp = datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)
            
            # Priority
            priority = self.read_uint8()
            
            # GPS data
            longitude = self.read_int32() / 10000000.0
            latitude = self.read_int32() / 10000000.0
            altitude = self.read_int16()
            angle = self.read_uint16()
            satellites = self.read_uint8()
            speed = self.read_uint16()
            
            # IO elements
            io_elements = self.parse_io_elements(codec_id)
            
            # Extract beacon data
            beacons = self.extract_beacons(io_elements)
            
            return {
                "timestamp": timestamp.isoformat(),
                "priority": priority,
                "gps": {
                    "lat": latitude,
                    "lng": longitude,
                    "altitude": altitude,
                    "angle": angle,
                    "satellites": satellites,
                    "speed": speed,
                },
                "io_elements": io_elements,
                "beacons": beacons,
            }
            
        except Exception as e:
            logger.error(f"Error parsing AVL record: {e}")
            return None
    
    def parse_io_elements(self, codec_id: int) -> dict:
        """Parse IO elements from AVL record"""
        io_elements = {}
        
        try:
            if codec_id == 0x8E:  # CODEC8 Extended
                # Event IO ID (2 bytes)
                event_io_id = self.read_uint16()
                # Total IO elements (2 bytes)
                total_io = self.read_uint16()
                
                # 1-byte IO elements
                n1 = self.read_uint16()
                for _ in range(n1):
                    io_id = self.read_uint16()
                    io_value = self.read_uint8()
                    io_elements[io_id] = io_value
                
                # 2-byte IO elements
                n2 = self.read_uint16()
                for _ in range(n2):
                    io_id = self.read_uint16()
                    io_value = self.read_uint16()
                    io_elements[io_id] = io_value
                
                # 4-byte IO elements
                n4 = self.read_uint16()
                for _ in range(n4):
                    io_id = self.read_uint16()
                    io_value = self.read_uint32()
                    io_elements[io_id] = io_value
                
                # 8-byte IO elements
                n8 = self.read_uint16()
                for _ in range(n8):
                    io_id = self.read_uint16()
                    io_value = self.read_uint64()
                    io_elements[io_id] = io_value
                
                # X-byte IO elements (variable length)
                nx = self.read_uint16()
                for _ in range(nx):
                    io_id = self.read_uint16()
                    io_len = self.read_uint16()
                    io_value = self.read_bytes(io_len)
                    # Store as hex string for beacon data
                    io_elements[io_id] = io_value.hex().upper()
                    
            else:  # CODEC8
                # Event IO ID (1 byte)
                event_io_id = self.read_uint8()
                # Total IO elements (1 byte)
                total_io = self.read_uint8()
                
                # 1-byte IO elements
                n1 = self.read_uint8()
                for _ in range(n1):
                    io_id = self.read_uint8()
                    io_value = self.read_uint8()
                    io_elements[io_id] = io_value
                
                # 2-byte IO elements
                n2 = self.read_uint8()
                for _ in range(n2):
                    io_id = self.read_uint8()
                    io_value = self.read_uint16()
                    io_elements[io_id] = io_value
                
                # 4-byte IO elements
                n4 = self.read_uint8()
                for _ in range(n4):
                    io_id = self.read_uint8()
                    io_value = self.read_uint32()
                    io_elements[io_id] = io_value
                
                # 8-byte IO elements
                n8 = self.read_uint8()
                for _ in range(n8):
                    io_id = self.read_uint8()
                    io_value = self.read_uint64()
                    io_elements[io_id] = io_value
                    
        except Exception as e:
            logger.error(f"Error parsing IO elements: {e}")
        
        return io_elements
    
    def extract_beacons(self, io_elements: dict) -> list:
        """Extract beacon data from IO elements"""
        beacons = []
        
        # Check for beacon IO elements (385-388 for beacons 1-4)
        for io_id in [385, 386, 387, 388]:
            if io_id in io_elements:
                beacon_data = io_elements[io_id]
                if isinstance(beacon_data, str) and len(beacon_data) >= 12:
                    # Extract MAC address (last 12 characters typically)
                    mac = beacon_data[-12:].upper()
                    
                    # Get additional info
                    known = KNOWN_BEACONS.get(mac, {})
                    
                    beacon = {
                        "mac": mac,
                        "raw_data": beacon_data,
                        "name": known.get("name", f"Beacon {io_id - 384}"),
                        "category": known.get("category", "Unknown"),
                        "sn": known.get("sn", ""),
                        "io_id": io_id,
                    }
                    
                    # Try to extract battery if present in raw data
                    if len(beacon_data) >= 14:
                        try:
                            battery_hex = beacon_data[-14:-12]
                            battery_raw = int(battery_hex, 16)
                            # Convert to voltage (approximate)
                            battery_volts = 2.0 + (battery_raw / 255.0) * 1.2
                            beacon["battery"] = round(battery_volts, 2)
                        except:
                            pass
                    
                    beacons.append(beacon)
        
        # Also check for magnet sensors
        magnet_sensors = {}
        for io_id in [331, 332, 333, 334]:
            if io_id in io_elements:
                sensor_num = io_id - 330
                magnet_sensors[f"magnet_{sensor_num}"] = io_elements[io_id]
        
        # Attach magnet sensors to first beacon if present
        if beacons and magnet_sensors:
            beacons[0]["magnet_sensors"] = magnet_sensors
        
        return beacons


# ============================================================================
# TCP SERVER
# ============================================================================

class TeltonikaServer:
    """TCP server for receiving Teltonika device data"""
    
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.server_socket = None
        self.running = False
        
    def start(self):
        """Start the TCP server"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(10)
        self.running = True
        
        logger.info(f"Teltonika TCP Server started on {self.host}:{self.port}")
        
        while self.running:
            try:
                client_socket, address = self.server_socket.accept()
                logger.info(f"Connection from {address}")
                
                # Handle client in a separate thread
                client_thread = threading.Thread(
                    target=self.handle_client,
                    args=(client_socket, address)
                )
                client_thread.daemon = True
                client_thread.start()
                
            except Exception as e:
                if self.running:
                    logger.error(f"Error accepting connection: {e}")
    
    def handle_client(self, client_socket: socket.socket, address: tuple):
        """Handle a connected Teltonika device"""
        imei = None
        
        try:
            # First, receive IMEI
            # Teltonika sends: 2 bytes length + IMEI string
            imei_data = client_socket.recv(1024)
            if len(imei_data) < 2:
                logger.warning(f"Invalid IMEI data from {address}")
                return
            
            imei_length = struct.unpack(">H", imei_data[:2])[0]
            imei = imei_data[2:2 + imei_length].decode('ascii')
            logger.info(f"Device IMEI: {imei}")
            
            # Send acknowledgment (0x01 = accepted)
            client_socket.send(b'\x01')
            
            # Get device info
            device_info = KNOWN_DEVICES.get(imei, {"name": f"Device_{imei[-6:]}", "tracker_id": 0})
            
            # Receive and process data packets
            while self.running:
                data = client_socket.recv(4096)
                if not data:
                    break
                
                logger.info(f"Received {len(data)} bytes from {imei}")
                logger.debug(f"Raw data: {data.hex()}")
                
                # Parse the packet
                parser = TeltonikaParser(data)
                parsed = parser.parse_avl_data()
                
                if parsed and parsed.get("records"):
                    # Send acknowledgment (number of records received)
                    num_records = len(parsed["records"])
                    client_socket.send(struct.pack(">I", num_records))
                    
                    # Store the latest data
                    with device_data_lock:
                        latest_record = parsed["records"][-1]
                        
                        device_data[imei] = {
                            "imei": imei,
                            "name": device_info["name"],
                            "tracker_id": device_info["tracker_id"],
                            "last_update": datetime.now(timezone.utc).isoformat(),
                            "gps": latest_record.get("gps", {}),
                            "beacons": [],
                            "all_records": parsed["records"][-10:],  # Keep last 10 records
                        }
                        
                        # Collect all beacons from all records
                        all_beacons = {}
                        for record in parsed["records"]:
                            for beacon in record.get("beacons", []):
                                mac = beacon.get("mac")
                                if mac:
                                    # Update with latest data
                                    all_beacons[mac] = {
                                        **beacon,
                                        "last_seen": record.get("timestamp"),
                                        "lat": record["gps"]["lat"],
                                        "lng": record["gps"]["lng"],
                                        "host_tracker": device_info["name"],
                                        "host_imei": imei,
                                    }
                        
                        device_data[imei]["beacons"] = list(all_beacons.values())
                        
                    logger.info(f"Processed {num_records} records, {len(all_beacons)} beacons from {imei}")
                    
                    # Log beacon details
                    for beacon in all_beacons.values():
                        logger.info(f"  Beacon: {beacon.get('mac')} - {beacon.get('name')}")
                
        except Exception as e:
            logger.error(f"Error handling client {address}: {e}")
            import traceback
            traceback.print_exc()
            
        finally:
            client_socket.close()
            logger.info(f"Connection closed: {address} (IMEI: {imei})")
    
    def stop(self):
        """Stop the TCP server"""
        self.running = False
        if self.server_socket:
            self.server_socket.close()


# ============================================================================
# REST API
# ============================================================================

app = Flask(__name__)
CORS(app)

@app.route("/")
def index():
    return jsonify({
        "service": "Teltonika Direct Server",
        "status": "running",
        "tcp_port": TCP_PORT,
        "api_port": API_PORT,
        "devices_connected": len(device_data),
    })

@app.route("/devices")
def get_devices():
    """Get all connected devices"""
    with device_data_lock:
        return jsonify(list(device_data.values()))

@app.route("/beacons")
def get_all_beacons():
    """Get all beacons from all devices"""
    all_beacons = []
    with device_data_lock:
        for device in device_data.values():
            for beacon in device.get("beacons", []):
                all_beacons.append(beacon)
    return jsonify(all_beacons)

@app.route("/data")
def get_data():
    """Get combined data (compatible with existing map)"""
    rows = []
    with device_data_lock:
        for imei, device in device_data.items():
            gps = device.get("gps", {})
            row = {
                "tracker_id": device.get("tracker_id", 0),
                "label": device.get("name", f"Device_{imei[-6:]}"),
                "lat": gps.get("lat", 0),
                "lng": gps.get("lng", 0),
                "speed": gps.get("speed", 0),
                "heading": gps.get("angle", 0),
                "last_update": device.get("last_update", ""),
                "beacons": device.get("beacons", []),
                "source": "teltonika_direct",
            }
            rows.append(row)
    
    return jsonify({"rows": rows, "source": "teltonika_direct_server"})


# ============================================================================
# MAIN
# ============================================================================

def run_api_server():
    """Run the Flask API server"""
    app.run(host="0.0.0.0", port=API_PORT, debug=False, threaded=True)

def main():
    print("=" * 60)
    print("TELTONIKA DIRECT TCP SERVER")
    print("=" * 60)
    print(f"TCP Port: {TCP_PORT} (for Teltonika devices)")
    print(f"API Port: {API_PORT} (for data access)")
    print()
    print("Configure your Teltonika device:")
    print(f"  Server: YOUR_IP_ADDRESS")
    print(f"  Port: {TCP_PORT}")
    print(f"  Protocol: TCP")
    print("=" * 60)
    
    # Start API server in a separate thread
    api_thread = threading.Thread(target=run_api_server)
    api_thread.daemon = True
    api_thread.start()
    logger.info(f"API server started on port {API_PORT}")
    
    # Start TCP server (blocking)
    tcp_server = TeltonikaServer(BIND_ADDRESS, TCP_PORT)
    try:
        tcp_server.start()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        tcp_server.stop()

if __name__ == "__main__":
    main()
