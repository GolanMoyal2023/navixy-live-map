"""
Create BLE tracking tables in SQL Server
Matching schema expected by db_helper.py
"""
import pyodbc

SQL_SERVER = r"localhost\SQL2025"
SQL_DATABASE = "2Plus_AssetTracking"
SQL_USER = "sa"
SQL_PASSWORD = "P@ssword0"

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SQL_SERVER};"
    f"DATABASE={SQL_DATABASE};"
    f"UID={SQL_USER};"
    f"PWD={SQL_PASSWORD};"
    f"TrustServerCertificate=yes;"
)
cursor = conn.cursor()

# Create BLE_Definitions table (lowercase column names to match db_helper)
cursor.execute("""
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Definitions' AND xtype='U')
CREATE TABLE BLE_Definitions (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100),
    category VARCHAR(50),
    ble_type VARCHAR(50),
    serial_number VARCHAR(50),
    asset_id VARCHAR(50),
    notes VARCHAR(500),
    created_at DATETIME DEFAULT GETDATE()
)
""")
print("BLE_Definitions: OK")

# Create BLE_Positions table (matching db_helper.py schema exactly)
# last_tracker_id is VARCHAR to store IMEI strings
cursor.execute("""
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Positions' AND xtype='U')
CREATE TABLE BLE_Positions (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) UNIQUE NOT NULL,
    lat DECIMAL(10,7),
    lng DECIMAL(10,7),
    last_tracker_id VARCHAR(50),
    last_tracker_label VARCHAR(100),
    last_update DATETIME DEFAULT GETDATE(),
    is_paired BIT DEFAULT 0,
    pairing_start DATETIME,
    pairing_duration_sec INT DEFAULT 0,
    battery_percent INT,
    magnet_status VARCHAR(50)
)
""")
print("BLE_Positions: OK")

# Create BLE_Movement_Log table
cursor.execute("""
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Movement_Log' AND xtype='U')
CREATE TABLE BLE_Movement_Log (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) NOT NULL,
    from_lat DECIMAL(10,7),
    from_lng DECIMAL(10,7),
    to_lat DECIMAL(10,7),
    to_lng DECIMAL(10,7),
    distance_meters DECIMAL(10,2),
    tracker_id VARCHAR(50),
    tracker_label VARCHAR(100),
    pairing_duration_sec INT,
    moved_at DATETIME DEFAULT GETDATE()
)
""")
print("BLE_Movement_Log: OK")

# Create BLE_Pairing_History table
cursor.execute("""
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Pairing_History' AND xtype='U')
CREATE TABLE BLE_Pairing_History (
    id INT IDENTITY(1,1) PRIMARY KEY,
    mac VARCHAR(20) NOT NULL,
    tracker_id VARCHAR(50),
    tracker_label VARCHAR(100),
    pairing_start DATETIME,
    pairing_end DATETIME,
    duration_sec INT,
    start_lat DECIMAL(10,7),
    start_lng DECIMAL(10,7),
    end_lat DECIMAL(10,7),
    end_lng DECIMAL(10,7),
    distance_traveled DECIMAL(10,2)
)
""")
print("BLE_Pairing_History: OK")

# Create Trackers table
cursor.execute("""
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Trackers' AND xtype='U')
CREATE TABLE Trackers (
    id VARCHAR(50) PRIMARY KEY,
    label VARCHAR(100),
    lat DECIMAL(10,7),
    lng DECIMAL(10,7),
    speed DECIMAL(6,2),
    device_type VARCHAR(50),
    category VARCHAR(50),
    battery_percent INT,
    last_update DATETIME DEFAULT GETDATE()
)
""")
print("Trackers: OK")

# Create System_Config table
cursor.execute("""
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='System_Config' AND xtype='U')
CREATE TABLE System_Config (
    config_key VARCHAR(100) PRIMARY KEY,
    config_value VARCHAR(500),
    updated_at DATETIME DEFAULT GETDATE()
)
""")
print("System_Config: OK")

conn.commit()

# Insert known beacons
beacons = [
    ("7cd9f407f95c", "Eybe2plus1", "Towed Device", "eye_beacon", "6204011070"),
    ("7cd9f4003536", "Eybe2plus2", "Equipment", "eye_beacon", "6204011168"),
    ("7cd9f4116ee7", "Eysen2plus", "Safety", "eye_sensor", "6134010143"),
]

for mac, name, cat, btype, sn in beacons:
    cursor.execute("""
        IF NOT EXISTS (SELECT 1 FROM BLE_Definitions WHERE mac = ?)
        INSERT INTO BLE_Definitions (mac, name, category, ble_type, serial_number)
        VALUES (?, ?, ?, ?, ?)
    """, mac, mac, name, cat, btype, sn)
    
conn.commit()
print("\nKnown beacons inserted!")

# Verify
cursor.execute("SELECT COUNT(*) FROM BLE_Definitions")
print(f"BLE_Definitions: {cursor.fetchone()[0]} rows")

cursor.execute("SELECT COUNT(*) FROM BLE_Positions")
print(f"BLE_Positions: {cursor.fetchone()[0]} rows")

cursor.execute("SELECT COUNT(*) FROM BLE_Movement_Log")
print(f"BLE_Movement_Log: {cursor.fetchone()[0]} rows")

conn.close()
print("\nAll tables created successfully!")
