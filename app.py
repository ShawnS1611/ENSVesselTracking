import streamlit as st
import pandas as pd
from datetime import date
import db_utils

# Initialize Database
db_utils.init_db()

st.set_page_config(page_title="Vessel ENS Tracker", page_icon="🚢", layout="wide")

st.title("🚢 Vessel Todo List - ENS Tracking")

# Styles
st.markdown("""
    <style>
    .stButton>button {
        width: 100%;
    }
    .declared-true {
        color: green;
        font-weight: bold;
    }
    .declared-false {
        color: red;
        font-weight: bold;
    }
    </style>
""", unsafe_allow_html=True)

tab1, tab2 = st.tabs(["📝 Input Voyage", "👀 View & Manage"])

with tab1:
    st.header("Add New Entry")
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.subheader("1. Vessel Details")
        # Check existing vessels
        existing_vessels = db_utils.get_vessels()
        
        vessel_option = st.radio("Select Vessel Source", ["Existing Vessel", "New Vessel"])
        
        selected_vessel_id = None
        
        if vessel_option == "Existing Vessel":
            if not existing_vessels.empty:
                vessel_choice = st.selectbox("Select Vessel", existing_vessels['name'].tolist())
                # Get ID
                selected_vessel_id = existing_vessels[existing_vessels['name'] == vessel_choice].iloc[0]['id']
            else:
                st.warning("No vessels found. Please add a new vessel.")
                vessel_option = "New Vessel" # Fallback
        
        if vessel_option == "New Vessel":
            new_vessel_name = st.text_input("Vessel Name")
            new_imo = st.text_input("IMO Number")
            if st.button("Save Vessel"):
                if new_vessel_name:
                    success, msg = db_utils.add_vessel(new_vessel_name, new_imo)
                    if success:
                        st.success(msg)
                        st.rerun()
                    else:
                        st.error(msg)
                else:
                    st.error("Vessel Name is required.")

    with col2:
        st.subheader("2. Voyage Details")
        voyage_number = st.text_input("Voyage Number (e.g. V265)")
        service_name = st.text_input("Service Name (e.g. Adriatic)", value="Adriatic")
        
        st.subheader("3. Port Calls (ENS Entries)")
        st.info("At least one entry is mandatory.")
        
        num_entries = st.number_input("Number of Port Calls", min_value=1, max_value=3, value=1)
        
        entries = []
        for i in range(int(num_entries)):
            ec1, ec2 = st.columns(2)
            with ec1:
                port = st.text_input(f"Port {i+1}", key=f"port_{i}")
            with ec2:
                arrival = st.date_input(f"Arrival Date {i+1}", min_value=date.today(), key=f"date_{i}")
            entries.append((port, arrival))

    st.markdown("---")
    if st.button("💾 Save Voyage & Entries", type="primary"):
        if not selected_vessel_id and vessel_option == "Existing Vessel":
             st.error("Please select a valid vessel.")
        elif not voyage_number:
            st.error("Voyage Number is required.")
        else:
            # If new vessel logic was skipped but text input filled, we might need to handle that, 
            # but for now we rely on the user adding vessel first if they chose "New Vessel".
            # Actually, let's allow creating vessel on fly if needed? 
            # Better to enforce step 1 save for robustness.
            
            if selected_vessel_id:
                # 1. Create Voyage
                voyage_id = db_utils.add_voyage(selected_vessel_id, voyage_number, service_name)
                
                # 2. Create Entries
                for port, arrival in entries:
                    if port: # Only add if port is specified
                        db_utils.add_ens_entry(voyage_id, port, arrival)
                
                st.success("Voyage and Entries saved successfully!")
                # Clear form (rerun)?
                # st.rerun()
            else:
                st.error("Please ensure a vessel is selected or created.")

with tab2:
    st.header("Manage Voyages")
    
    df = db_utils.get_voyages_with_details()
    
    if not df.empty:
        # Convert date column to datetime
        df['arrival_date'] = pd.to_datetime(df['arrival_date']).dt.date
        
        # Filters
        filter_col1, filter_col2 = st.columns(2)
        with filter_col1:
            show_past = st.checkbox("Show Past Voyages", value=False)
        
        today = date.today()
        if not show_past:
            df = df[df['arrival_date'] >= today]
            
        st.dataframe(
            df[['vessel_name', 'voyage_number', 'port', 'arrival_date', 'is_declared']],
            use_container_width=True,
            hide_index=True
        )
        
        st.subheader("Update Status")
        for index, row in df.iterrows():
            col1, col2, col3, col4, col5 = st.columns([2, 1, 1, 1, 1])
            with col1:
                st.write(f"**{row['vessel_name']}** ({row['voyage_number']})")
            with col2:
                st.write(f"{row['port']}")
            with col3:
                st.write(f"{row['arrival_date']}")
            with col4:
                status = "✅ Declared" if row['is_declared'] else "❌ Pending"
                st.write(status)
            with col5:
                # Action button to toggle
                if not row['is_declared']:
                    if st.button("Mark Declared", key=f"dec_{row['entry_id']}"):
                        db_utils.update_declaration_status(row['entry_id'], 1)
                        st.rerun()
                else:
                    if st.button("Undo", key=f"undo_{row['entry_id']}"):
                        db_utils.update_declaration_status(row['entry_id'], 0)
                        st.rerun()
                
                if st.button("Delete", key=f"del_{row['entry_id']}"):
                     db_utils.delete_entry(row['entry_id'])
                     st.rerun()
    else:
        st.info("No voyages found. Go to the Input Voyage tab to add some!")
