import sqlite3
import pandas as pd
from datetime import datetime

DB_NAME = "vessels.db"

def get_connection():
    return sqlite3.connect(DB_NAME)

def init_db():
    conn = get_connection()
    c = conn.cursor()
    
    # Create Vessels table
    c.execute('''
        CREATE TABLE IF NOT EXISTS vessels (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            imo_number TEXT
        )
    ''')
    
    # Create Voyages table
    c.execute('''
        CREATE TABLE IF NOT EXISTS voyages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vessel_id INTEGER NOT NULL,
            voyage_number TEXT NOT NULL,
            service_name TEXT,
            FOREIGN KEY (vessel_id) REFERENCES vessels (id)
        )
    ''')
    
    # Create ENS Entries table
    c.execute('''
        CREATE TABLE IF NOT EXISTS ens_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            voyage_id INTEGER NOT NULL,
            port TEXT NOT NULL,
            arrival_date DATE NOT NULL,
            is_declared BOOLEAN DEFAULT 0,
            uploaded_files TEXT,
            FOREIGN KEY (voyage_id) REFERENCES voyages (id)
        )
    ''')
    
    # Migration: Check if uploaded_files exists
    c.execute("PRAGMA table_info(ens_entries)")
    columns = [info[1] for info in c.fetchall()]
    if "uploaded_files" not in columns:
        c.execute("ALTER TABLE ens_entries ADD COLUMN uploaded_files TEXT")
        print("Migrated: Added uploaded_files column to ens_entries")
    
    conn.commit()
    conn.close()

def add_vessel(name, imo_number):
    conn = get_connection()
    c = conn.cursor()
    try:
        c.execute("INSERT INTO vessels (name, imo_number) VALUES (?, ?)", (name, imo_number))
        conn.commit()
        return True, "Vessel added successfully."
    except sqlite3.IntegrityError:
        return False, "Vessel with this name already exists."
    finally:
        conn.close()

def delete_vessel(name):
    conn = get_connection()
    c = conn.cursor()
    # Check if used? For now, we just delete. The Inner Join in view will hide orphans.
    # Better: Cascading delete manually if we want to be clean, but user might want to keep history?
    # User just asked to remove from list.
    # Let's delete the vessel.
    c.execute("DELETE FROM vessels WHERE name = ?", (name,))
    rows = c.rowcount
    conn.commit()
    conn.close()
    return rows > 0, "Vessel deleted." if rows > 0 else "Vessel not found."

def get_vessels():
    conn = get_connection()
    df = pd.read_sql_query("SELECT * FROM vessels", conn)
    conn.close()
    return df

def add_voyage(vessel_id, voyage_number, service_name):
    conn = get_connection()
    c = conn.cursor()
    c.execute("INSERT INTO voyages (vessel_id, voyage_number, service_name) VALUES (?, ?, ?)", 
              (vessel_id, voyage_number, service_name))
    voyage_id = c.lastrowid
    conn.commit()
    conn.close()
    return voyage_id

def add_ens_entry(voyage_id, port, arrival_date, uploaded_files=""):
    conn = get_connection()
    c = conn.cursor()
    c.execute("INSERT INTO ens_entries (voyage_id, port, arrival_date, is_declared, uploaded_files) VALUES (?, ?, ?, 0, ?)", 
              (voyage_id, port, arrival_date, uploaded_files))
    conn.commit()
    conn.close()

def get_voyages_with_details():
    conn = get_connection()
    query = '''
        SELECT 
            v.id as voyage_id,
            ves.name as vessel_name,
            v.voyage_number,
            v.service_name,
            e.id as entry_id,
            e.port,
            e.arrival_date,
            e.is_declared,
            e.uploaded_files
        FROM voyages v
        JOIN vessels ves ON v.vessel_id = ves.id
        JOIN ens_entries e ON v.id = e.voyage_id
        ORDER BY e.arrival_date DESC
    '''
    df = pd.read_sql_query(query, conn)
    conn.close()
    return df

def update_declaration_status(entry_id, status):
    conn = get_connection()
    c = conn.cursor()
    c.execute("UPDATE ens_entries SET is_declared = ? WHERE id = ?", (status, entry_id))
    conn.commit()
    conn.close()

def delete_entry(entry_id):
    conn = get_connection()
    c = conn.cursor()
    c.execute("DELETE FROM ens_entries WHERE id = ?", (entry_id,))
    conn.commit()
    conn.commit()
    conn.close()

def update_ens_entry(entry_id, port, arrival_date, uploaded_files=None):
    conn = get_connection()
    c = conn.cursor()
    if uploaded_files is not None:
        c.execute("UPDATE ens_entries SET port = ?, arrival_date = ?, uploaded_files = ? WHERE id = ?", (port, arrival_date, uploaded_files, entry_id))
    else:
        c.execute("UPDATE ens_entries SET port = ?, arrival_date = ? WHERE id = ?", (port, arrival_date, entry_id))
    conn.commit()
    conn.close()

def update_voyage(voyage_id, voyage_number, service_name=None):
    conn = get_connection()
    c = conn.cursor()
    if service_name:
         c.execute("UPDATE voyages SET voyage_number = ?, service_name = ? WHERE id = ?", (voyage_number, service_name, voyage_id))
    else:
         c.execute("UPDATE voyages SET voyage_number = ? WHERE id = ?", (voyage_number, voyage_id))
    conn.commit()
    conn.close()

    conn.commit()
    conn.close()

def get_voyage_entries(voyage_id):
    conn = get_connection()
    c = conn.cursor()
    c.execute("SELECT port, arrival_date FROM ens_entries WHERE voyage_id = ? ORDER BY arrival_date ASC", (voyage_id,))
    entries = c.fetchall()
    conn.close()
    return entries
    
def get_upcoming_entries(days=7):
    """
    Returns entries arriving between today and today + days.
    """
    conn = get_connection()
    today_str = datetime.now().strftime('%Y-%m-%d')
    # For SQLite, we can compute end date or just filter in Python.
    # Simple SQL date compare works if format is YYYY-MM-DD
    
    # We'll fetch future entries >= today, then filter top N or by date in Python if we want strict range
    # Or strict SQL: date('now') to date('now', '+7 days')
    
    query = """
    SELECT 
        v.name as vessel, 
        vo.voyage_number, 
        vo.service_name,
        e.port, 
        e.arrival_date,
        e.id as entry_id
    FROM ens_entries e
    JOIN voyages vo ON e.voyage_id = vo.id
    JOIN vessels v ON vo.vessel_id = v.id
    WHERE e.arrival_date >= date('now') 
    AND e.arrival_date <= date('now', '+' || ? || ' days')
    ORDER BY e.arrival_date ASC
    """
    
    try:
        df = pd.read_sql_query(query, conn, params=(str(days),))
    except Exception as e:
        print(f"Error fetching upcoming: {e}")
        df = pd.DataFrame()
        
    conn.close()
    return df

def duplicate_voyage(original_voyage_id, new_voyage_number, new_start_date_str):
    """
    Clones a voyage and its entries.
    new_start_date_str: YYYY-MM-DD string for the FIRST port call.
    Subsequent ports will be offset from the first port based on the original schedule.
    """
    conn = get_connection()
    c = conn.cursor()
    
    # 1. Get Original Voyage Details
    c.execute("SELECT vessel_id, service_name FROM voyages WHERE id = ?", (original_voyage_id,))
    voyage_row = c.fetchone()
    if not voyage_row:
        conn.close()
        return False, "Original voyage not found."
        
    vessel_id, service_name = voyage_row
    
    # 2. Get Original Entries
    entries = get_voyage_entries(original_voyage_id)
    if not entries:
        conn.close()
        return False, "Original voyage has no entries to clone."
        
    # 3. Calculate Date Offsets
    # entries is list of (port, date_str) sorted by date
    try:
        first_orig_date = datetime.strptime(entries[0][1], '%Y-%m-%d').date()
        new_start_date = datetime.strptime(new_start_date_str, '%Y-%m-%d').date()
    except ValueError:
        conn.close()
        return False, "Invalid date format."
        
    day_diff = (new_start_date - first_orig_date).days
    
    # 4. Create New Voyage
    c.execute("INSERT INTO voyages (vessel_id, voyage_number, service_name) VALUES (?, ?, ?)", 
              (vessel_id, new_voyage_number, service_name))
    new_voyage_id = c.lastrowid
    
    # 5. Create New Entries with Shifted Dates
    for port, orig_date_str in entries:
        orig_date = datetime.strptime(orig_date_str, '%Y-%m-%d').date()
        new_date = orig_date + pd.Timedelta(days=day_diff)
        new_date_str = new_date.strftime('%Y-%m-%d')
        
        c.execute("INSERT INTO ens_entries (voyage_id, port, arrival_date, is_declared) VALUES (?, ?, ?, 0)", 
              (new_voyage_id, port, new_date_str))
              
    conn.commit()
    conn.close()
    return True, "Voyage cloned successfully."

# Initialize DB on import
if __name__ == "__main__":
    init_db()
    print("Database initialized.")
