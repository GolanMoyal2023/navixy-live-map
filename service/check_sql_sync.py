import pyodbc


CONN_STR = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=localhost\\SQL2025;"
    "DATABASE=2Plus_AssetTracking;"
    "UID=sa;"
    "PWD=P@ssword0;"
    "TrustServerCertificate=yes;"
)


def main() -> None:
    conn = pyodbc.connect(CONN_STR)
    cur = conn.cursor()

    for view in ("vw_BLE_Current", "vw_BLE_Diagnostics"):
        cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID(?))", view)
        row = cur.fetchone()
        print(f"\n=== {view} definition ===")
        print((row[0] if row else "") or "<missing>")

    queries = [
        "SELECT COUNT(1) AS cnt FROM BLE_Scans",
        "SELECT COUNT(1) AS cnt FROM BLE_Positions",
        "SELECT COUNT(1) AS cnt FROM vw_BLE_Current",
        "SELECT COUNT(1) AS cnt FROM vw_BLE_Diagnostics",
        "SELECT TOP 5 mac, tracker_imei, rssi, battery_percent, scan_time FROM BLE_Scans ORDER BY scan_time DESC",
        "SELECT TOP 5 mac, latest_tracker, latest_scan_time, battery_percent, rssi FROM vw_BLE_Current ORDER BY latest_scan_time DESC",
        "SELECT TOP 5 mac, tracker_imei, rssi, battery_percent, scan_time FROM vw_BLE_Diagnostics ORDER BY scan_time DESC",
    ]

    for q in queries:
        print(f"\nSQL> {q}")
        cur.execute(q)
        for row in cur.fetchall():
            print(tuple(row))

    conn.close()


if __name__ == "__main__":
    main()
