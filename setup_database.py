"""
BLE Tracking Database Setup Script
Creates all required tables in SQL Server for BLE position tracking
"""

import pyodbc
import sys

# Fix console encoding for emojis
sys.stdout.reconfigure(encoding='utf-8')

# SQL Server connection settings
SQL_SERVER = r"localhost\SQL2025"
SQL_DATABASE = "2Plus_AssetTracking"
SQL_USER = "sa"
SQL_PASSWORD = "P@ssword0"

def get_master_connection():
    """Get SQL Server connection to master database"""
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE=master;"
        f"UID={SQL_USER};"
        f"PWD={SQL_PASSWORD};"
        f"TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)

def get_connection():
    """Get SQL Server connection to target database"""
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE={SQL_DATABASE};"
        f"UID={SQL_USER};"
        f"PWD={SQL_PASSWORD};"
        f"TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)

def ensure_database_exists():
    """Create the database if it doesn't exist"""
    print("Checking if database exists...")
    try:
        conn = get_master_connection()
        conn.autocommit = True
        cursor = conn.cursor()
        
        cursor.execute(f"""
            IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '{SQL_DATABASE}')
            BEGIN
                CREATE DATABASE [{SQL_DATABASE}]
                PRINT 'Database created'
            END
            ELSE
            BEGIN
                PRINT 'Database already exists'
            END
        """)
        conn.close()
        print(f"[OK] Database {SQL_DATABASE} ready")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to create database: {e}")
        return False

def create_schema():
    """Create all required tables"""
    
    print("=" * 60)
    print("BLE Tracking Database Setup")
    print("=" * 60)
    
    # First ensure database exists
    if not ensure_database_exists():
        return False
    
    try:
        conn = get_connection()
        cursor = conn.cursor()
        print(f"[OK] Connected to {SQL_SERVER}/{SQL_DATABASE}")
    except Exception as e:
        print(f"[ERROR] Connection failed: {e}")
        return False
    
    # List of tables to create
    tables = [
        # BLE Positions - Current position of each BLE
        """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Positions' AND xtype='U')
        CREATE TABLE BLE_Positions (
            id INT IDENTITY(1,1) PRIMARY KEY,
            mac VARCHAR(20) NOT NULL UNIQUE,
            name VARCHAR(100),
            category VARCHAR(50),
            ble_type VARCHAR(50) DEFAULT 'eye_beacon',
            serial_number VARCHAR(50),
            lat FLOAT,
            lng FLOAT,
            last_tracker_id INT,
            last_tracker_label VARCHAR(100),
            last_update DATETIME DEFAULT GETDATE(),
            is_paired BIT DEFAULT 0,
            pairing_start DATETIME,
            pairing_duration_sec INT DEFAULT 0,
            battery_percent INT,
            magnet_status VARCHAR(20),
            created_at DATETIME DEFAULT GETDATE()
        )
        """,
        
        # BLE Movement Log - History of position changes
        """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Movement_Log' AND xtype='U')
        CREATE TABLE BLE_Movement_Log (
            id INT IDENTITY(1,1) PRIMARY KEY,
            mac VARCHAR(20) NOT NULL,
            from_lat FLOAT,
            from_lng FLOAT,
            to_lat FLOAT,
            to_lng FLOAT,
            distance_meters FLOAT,
            tracker_id INT,
            tracker_label VARCHAR(100),
            pairing_duration_sec INT,
            movement_time DATETIME DEFAULT GETDATE()
        )
        """,
        
        # Trackers - GSE/Vehicle information
        """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Trackers' AND xtype='U')
        CREATE TABLE Trackers (
            id INT PRIMARY KEY,
            label VARCHAR(100),
            device_type VARCHAR(50),
            category VARCHAR(50),
            lat FLOAT,
            lng FLOAT,
            speed FLOAT,
            last_update DATETIME,
            battery_percent INT,
            created_at DATETIME DEFAULT GETDATE()
        )
        """,
        
        # BLE Definitions - Known BLE beacons with metadata
        """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Definitions' AND xtype='U')
        CREATE TABLE BLE_Definitions (
            id INT IDENTITY(1,1) PRIMARY KEY,
            mac VARCHAR(20) NOT NULL UNIQUE,
            name VARCHAR(100) NOT NULL,
            category VARCHAR(50),
            ble_type VARCHAR(50) DEFAULT 'eye_beacon',
            serial_number VARCHAR(50),
            asset_id VARCHAR(50),
            notes TEXT,
            created_at DATETIME DEFAULT GETDATE(),
            updated_at DATETIME DEFAULT GETDATE()
        )
        """,
        
        # Pairing History - Track which tracker towed which BLE
        """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='BLE_Pairing_History' AND xtype='U')
        CREATE TABLE BLE_Pairing_History (
            id INT IDENTITY(1,1) PRIMARY KEY,
            mac VARCHAR(20) NOT NULL,
            tracker_id INT NOT NULL,
            tracker_label VARCHAR(100),
            pairing_start DATETIME,
            pairing_end DATETIME,
            duration_sec INT,
            start_lat FLOAT,
            start_lng FLOAT,
            end_lat FLOAT,
            end_lng FLOAT,
            distance_traveled FLOAT
        )
        """,
        
        # System Config - Store configuration values
        """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='System_Config' AND xtype='U')
        CREATE TABLE System_Config (
            id INT IDENTITY(1,1) PRIMARY KEY,
            config_key VARCHAR(100) NOT NULL UNIQUE,
            config_value VARCHAR(500),
            description VARCHAR(500),
            updated_at DATETIME DEFAULT GETDATE()
        )
        """
    ]
    
    # Create each table
    for i, sql in enumerate(tables):
        table_name = sql.split("CREATE TABLE ")[1].split(" ")[0] if "CREATE TABLE" in sql else f"Table {i+1}"
        try:
            cursor.execute(sql)
            conn.commit()
            print(f"[OK] Created/verified: {table_name}")
        except Exception as e:
            print(f"[ERROR] Error creating {table_name}: {e}")
    
    # Insert default BLE definitions
    ble_defaults = [
        ("f008d1d55c3c", "Eybe2plus1", "Towed Device", "eye_beacon", "6204011070"),
        ("f008d1d54c72", "Eybe2plus2", "Equipment", "eye_beacon", "6204011168"),
        ("f008d1d516fb", "Eysen2plus", "Safety", "eye_sensor", "6134010143"),
    ]
    
    print("\nInserting default BLE definitions...")
    for mac, name, category, ble_type, sn in ble_defaults:
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT 1 FROM BLE_Definitions WHERE mac = ?)
                INSERT INTO BLE_Definitions (mac, name, category, ble_type, serial_number)
                VALUES (?, ?, ?, ?, ?)
            """, mac, mac, name, category, ble_type, sn)
            conn.commit()
            print(f"  [OK] {name} ({mac})")
        except Exception as e:
            print(f"  [WARN] {name}: {e}")
    
    # Insert default config values
    config_defaults = [
        ("PAIRING_THRESHOLD_SECONDS", "60", "Seconds required to confirm BLE is being towed"),
        ("BLE_STALE_DAYS", "7", "Days to keep BLE position without update"),
        ("POSITION_CHANGE_THRESHOLD", "10", "Meters movement required to update position"),
        ("REFRESH_INTERVAL_MS", "5000", "Map refresh interval in milliseconds"),
    ]
    
    print("\nInserting default config values...")
    for key, value, desc in config_defaults:
        try:
            cursor.execute("""
                IF NOT EXISTS (SELECT 1 FROM System_Config WHERE config_key = ?)
                INSERT INTO System_Config (config_key, config_value, description)
                VALUES (?, ?, ?)
            """, key, key, value, desc)
            conn.commit()
            print(f"  [OK] {key} = {value}")
        except Exception as e:
            print(f"  [WARN] {key}: {e}")
    
    # Create indexes for performance
    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_ble_positions_mac ON BLE_Positions(mac)",
        "CREATE INDEX IF NOT EXISTS idx_ble_movement_mac ON BLE_Movement_Log(mac)",
        "CREATE INDEX IF NOT EXISTS idx_ble_movement_time ON BLE_Movement_Log(movement_time)",
        "CREATE INDEX IF NOT EXISTS idx_pairing_mac ON BLE_Pairing_History(mac)",
        "CREATE INDEX IF NOT EXISTS idx_pairing_tracker ON BLE_Pairing_History(tracker_id)",
    ]
    
    print("\nCreating indexes...")
    for idx_sql in indexes:
        try:
            # SQL Server doesn't support IF NOT EXISTS for indexes, so we use a different approach
            idx_name = idx_sql.split("CREATE INDEX IF NOT EXISTS ")[1].split(" ")[0]
            table_name = idx_sql.split(" ON ")[1].split("(")[0]
            column = idx_sql.split("(")[1].split(")")[0]
            
            check_sql = f"""
                IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = '{idx_name}')
                CREATE INDEX {idx_name} ON {table_name}({column})
            """
            cursor.execute(check_sql)
            conn.commit()
            print(f"  [OK] Index: {idx_name}")
        except Exception as e:
            print(f"  [WARN] Index error: {e}")
    
    # Verify tables created
    print("\n" + "=" * 60)
    print("Database Schema Summary:")
    print("=" * 60)
    
    cursor.execute("""
        SELECT TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_NAME
    """)
    tables = cursor.fetchall()
    
    for table in tables:
        cursor.execute(f"SELECT COUNT(*) FROM [{table[0]}]")
        count = cursor.fetchone()[0]
        print(f"  [TABLE] {table[0]}: {count} rows")
    
    conn.close()
    
    print("\n" + "=" * 60)
    print("[SUCCESS] DATABASE SETUP COMPLETE!")
    print("=" * 60)
    
    return True

if __name__ == "__main__":
    create_schema()
