import db_utils
from datetime import date

def test_db():
    print("Testing DB functionality...")
    db_utils.init_db()
    
    # 1. Add Vessel
    print("Adding vessel...")
    success, msg = db_utils.add_vessel("TEST VESSEL", "1234567")
    print(msg)
    
    # 2. Get Vessel
    df = db_utils.get_vessels()
    if not df.empty:
        v_id = int(df.iloc[0]['id'])
        print(f"Vessel ID: {v_id}")
        
        # 3. Add Voyage
        print("Adding voyage...")
        voyage_id = db_utils.add_voyage(v_id, "V001", "Test Service")
        print(f"Voyage ID: {voyage_id}")
        
        # 4. Add Entry
        print("Adding entry...")
        db_utils.add_ens_entry(voyage_id, "Rotterdam", date.today())
        
        # 5. Check
        print("Fetching details...")
        details = db_utils.get_voyages_with_details()
        print(details)
    else:
        print("Failed to add vessel.")

if __name__ == "__main__":
    test_db()
