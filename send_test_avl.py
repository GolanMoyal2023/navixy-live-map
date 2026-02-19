#!/usr/bin/env python3
"""
Send one fake Teltonika CODEC8 Extended packet to the local broker (127.0.0.1:15027).
Use this to get real-looking data on the map when running locally without hardware.

Usage:
  .\\.venv\\Scripts\\python.exe send_test_avl.py

Then open http://127.0.0.1:8080/index.html (Data: Direct) to see 1 tracker + 1 BLE.
"""
import socket
import struct
import time

TCP_HOST = "127.0.0.1"
TCP_PORT = 15027
IMEI = "350012345678901"  # fake IMEI for test tracker

# One known beacon MAC (Eybe2plus1) so broker matches it
BEACON_MAC = bytes.fromhex("7cd9f407f95c")  # 6 bytes
# Ben Gurion area
LAT = 32.009
LNG = 34.876


def build_codec8_extended_packet() -> bytes:
    """Build one AVL record with GPS + one BLE beacon (element 385)."""
    timestamp_ms = int(time.time() * 1000)
    # Element 385 payload: num_beacons=1, MAC(6), rssi(1), battery(1), flags(1)
    beacon_payload = (
        b"\x01"  # num_beacons
        + BEACON_MAC
        + struct.pack("b", -50)  # rssi
        + bytes([85])   # battery %
        + bytes([0])    # flags
    )
    assert len(beacon_payload) == 10

    # AVL record: timestamp(8) + priority(1) + GPS(15) + event(2) + total_io(2)
    # + four counts 2 bytes each = 8 zeros + var_count(2) + id(2)+len(2)+value(10)
    record = (
        struct.pack(">Q", timestamp_ms)
        + bytes([0])  # priority
        + struct.pack(">i", int(LNG * 10000000))  # longitude
        + struct.pack(">i", int(LAT * 10000000))  # latitude
        + struct.pack(">H", 50)   # altitude
        + struct.pack(">H", 0)    # angle
        + bytes([10])             # satellites
        + struct.pack(">H", 0)   # speed km/h
        + struct.pack(">H", 0)   # event_id
        + struct.pack(">H", 0)   # total_elements (fixed-size IO count)
        + struct.pack(">H", 0)   # count 1-byte
        + struct.pack(">H", 0)   # count 2-byte
        + struct.pack(">H", 0)   # count 4-byte
        + struct.pack(">H", 0)   # count 8-byte
        + struct.pack(">H", 1)   # variable-length count = 1
        + struct.pack(">H", 385) # IO id 385 (BLE beacons)
        + struct.pack(">H", len(beacon_payload))
        + beacon_payload
    )

    # Packet: preamble 0 (4) + data_length (4) + codec (1) + num_records (1) + record
    data_len = 1 + 1 + len(record)
    packet = (
        struct.pack(">I", 0)
        + struct.pack(">I", data_len)
        + bytes([0x8E])  # CODEC8 Extended
        + bytes([1])     # num_records
        + record
    )
    return packet


def main():
    print(f"Connecting to {TCP_HOST}:{TCP_PORT} ...")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(10)
    try:
        s.connect((TCP_HOST, TCP_PORT))
    except ConnectionRefusedError:
        print("ERROR: Broker not running. Start it first:")
        print("  .\\.venv\\Scripts\\python.exe teltonika_broker.py")
        return 1

    # Send IMEI
    imei_bytes = IMEI.encode("ascii")
    s.send(struct.pack(">H", len(imei_bytes)) + imei_bytes)
    ack = s.recv(1)
    if ack != b"\x01":
        print("ERROR: Broker rejected IMEI")
        return 1
    print("IMEI accepted.")

    # Send AVL packet
    packet = build_codec8_extended_packet()
    s.send(packet)
    recv_ack = s.recv(4)
    if len(recv_ack) == 4:
        num = struct.unpack(">I", recv_ack)[0]
        print(f"Broker acknowledged {num} record(s).")
    s.close()

    print("Done. Open http://127.0.0.1:8080/index.html (Data: Direct) to see the tracker and BLE.")
    return 0


if __name__ == "__main__":
    exit(main())
