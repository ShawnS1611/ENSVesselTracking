import db_utils
import pandas as pd
import sqlite3

def test_nan_fix():
    print("Testing NaN Fix...")
    db_utils.init_db()
    
    # 1. Create a Vessel and Voyage but NO entries
    db_utils.add_vessel("Ghost Vessel", "000000")
    df_v = db_utils.get_vessels()
    vid = int(df_v[df_v['name'] == "Ghost Vessel"].iloc[0]['id'])
    
    voy_id = db_utils.add_voyage(vid, "V_GHOST", "Ghost Service")
    print(f"Created Empty Voyage ID: {voy_id}")
    
    # 2. Get Data using the view function
    df = db_utils.get_voyages_with_details()
    
    # 3. Check if this voyage appears
    # With INNER JOIN, it should NOT appear.
    # With LEFT JOIN, it WOULD appear with entry_id = NaN
    
    ghost_rows = df[df['voyage_id'] == voy_id]
    print(f"Rows found for Ghost Voyage: {len(ghost_rows)}")
    
    if ghost_rows.empty:
        print("PASS: Empty voyage is excluded from view.")
    else:
        print("FAIL: Empty voyage found in view!")
        print(ghost_rows)
        # Check for NaN
        if ghost_rows['entry_id'].isna().any():
            print("CRITICAL FAIL: Found NaN entry_id")
            exit(1)

    print("NaN Fix Verification PASSED!")

if __name__ == "__main__":
    try:
        test_nan_fix()
    except Exception as e:
        print(f"Error: {e}")
        exit(1)
