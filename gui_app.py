import tkinter as tk
from tkinter import ttk, messagebox
import db_utils
from datetime import datetime
import pandas as pd
from tkcalendar import DateEntry

COMMON_PORTS = [
"ESVLC","GBFLX","BEANR","NLRTM","ITSAL","GBLIV","IEDUB","CYLMS"
]

SERVICE_NAMES = [
    "North Europe Aegean",
    "North Europe Italy Express",
    "West Coast UK",
    "West Med",
    "Adriatic"
]

class VesselApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Vessel ENS Tracker")
        self.geometry("800x600")
        
        # Init DB
        db_utils.init_db()
        
        # Tabs
        self.notebook = ttk.Notebook(self)
        self.tab_input = ttk.Frame(self.notebook)
        self.tab_view = ttk.Frame(self.notebook)
        
        self.notebook.add(self.tab_input, text="Input Voyage")
        self.notebook.add(self.tab_view, text="View & Manage")
        self.notebook.pack(expand=True, fill='both')
        
        self.setup_input_tab()
        self.setup_view_tab()
        
    def setup_input_tab(self):
        frame = ttk.Frame(self.tab_input, padding=20)
        frame.pack(fill='both', expand=True)
        
        # --- Vessel Selection ---
        ttk.Label(frame, text="1. Vessel Details", font=("Arial", 12, "bold")).grid(row=0, column=0, sticky="w", pady=(0, 10))
        
        self.vessel_var = tk.StringVar()
        self.vessel_combo = ttk.Combobox(frame, textvariable=self.vessel_var, state="readonly")
        self.vessel_combo.grid(row=1, column=0, sticky="ew", padx=5)
        self.refresh_vessels()
        
        ttk.Button(frame, text="+ New Vessel", command=self.add_vessel_popup).grid(row=1, column=1, padx=5)
        ttk.Button(frame, text="- Delete Vessel", command=self.delete_vessel_action).grid(row=1, column=2, padx=5)
        
        # --- Voyage Details ---
        ttk.Label(frame, text="2. Voyage Details", font=("Arial", 12, "bold")).grid(row=2, column=0, sticky="w", pady=(20, 10))
        
        ttk.Label(frame, text="Voyage Number:").grid(row=3, column=0, sticky="w", padx=5)
        self.voyage_num_entry = ttk.Entry(frame)
        self.voyage_num_entry.grid(row=3, column=1, sticky="ew", padx=5)
        
        ttk.Label(frame, text="Service Name:").grid(row=4, column=0, sticky="w", padx=5)
        self.service_entry = ttk.Combobox(frame, values=SERVICE_NAMES)
        self.service_entry.current(4) # Default to Adriatic
        self.service_entry.grid(row=4, column=1, sticky="ew", padx=5)
        
        # --- Entries ---
        ttk.Label(frame, text="3. Port Calls (ENS Entries)", font=("Arial", 12, "bold")).grid(row=5, column=0, sticky="w", pady=(20, 10))
        ttk.Label(frame, text="Format: YYYY-MM-DD").grid(row=5, column=1, sticky="e")
        
        self.entry_widgets = []
        for i in range(3):
            lbl_port = ttk.Label(frame, text=f"Port {i+1}:")
            lbl_port.grid(row=6+i, column=0, sticky="e", padx=5, pady=2)
            
            ent_port = ttk.Combobox(frame, values=COMMON_PORTS)
            ent_port.grid(row=6+i, column=1, sticky="ew", padx=5, pady=2)
            
            lbl_date = ttk.Label(frame, text=f"Date {i+1}:")
            lbl_date.grid(row=6+i, column=2, sticky="e", padx=5, pady=2)
            
            ent_date = DateEntry(frame, width=12, background='darkblue', foreground='white', borderwidth=2, date_pattern='yyyy-mm-dd')
            ent_date.grid(row=6+i, column=3, sticky="ew", padx=5, pady=2)
            
            self.entry_widgets.append((ent_port, ent_date))
            
        # --- Save Button ---
        ttk.Button(frame, text="💾 Save Voyage & Entries", command=self.save_data).grid(row=10, column=0, columnspan=4, pady=30, sticky="ew")

    def setup_view_tab(self):
        frame = ttk.Frame(self.tab_view, padding=10)
        frame.pack(fill='both', expand=True)
        
        # --- Filter Frame ---
        filter_frame = ttk.LabelFrame(frame, text="Filters", padding=10)
        filter_frame.pack(fill='x', pady=(0, 10))
        
        # Row 1 of filters
        # Search
        ttk.Label(filter_frame, text="Search (Vessel/Voyage):").grid(row=0, column=0, padx=5, sticky="w")
        self.search_var = tk.StringVar()
        self.search_var.trace("w", lambda name, index, mode: self.load_voyages())
        search_entry = ttk.Entry(filter_frame, textvariable=self.search_var)
        search_entry.grid(row=0, column=1, padx=5, sticky="ew")
        
        # Port Filter
        ttk.Label(filter_frame, text="Filter Port:").grid(row=0, column=2, padx=5, sticky="w")
        self.port_filter_var = tk.StringVar()
        port_cb = ttk.Combobox(filter_frame, textvariable=self.port_filter_var, values=["All"] + COMMON_PORTS, state="readonly")
        port_cb.grid(row=0, column=3, padx=5, sticky="ew")
        port_cb.bind("<<ComboboxSelected>>", lambda e: self.load_voyages())
        port_cb.current(0)
        
        # Show Past
        self.show_past_var = tk.BooleanVar(value=False)
        cb_past = ttk.Checkbutton(filter_frame, text="Show Past Voyages", variable=self.show_past_var, command=self.load_voyages)
        cb_past.grid(row=0, column=4, padx=15, sticky="w")
        
        # Clear Button
        ttk.Button(filter_frame, text="Clear Filters", command=self.clear_filters).grid(row=0, column=5, padx=5, sticky="e")
        
        filter_frame.columnconfigure(1, weight=1) # Search expands
        
        # Treeview
        columns = ("vessel", "service", "voyage", "port", "date", "status")
        self.tree = ttk.Treeview(frame, columns=columns, show="headings", selectmode="extended")
        
        self.tree.heading("vessel", text="Vessel")
        self.tree.heading("service", text="Service")
        self.tree.heading("voyage", text="Voyage")
        self.tree.heading("port", text="Port")
        self.tree.heading("date", text="Arrival Date")
        self.tree.heading("status", text="Declared?")
        
        self.tree.column("vessel", width=150)
        self.tree.column("service", width=100)
        self.tree.column("voyage", width=80)
        self.tree.column("port", width=100)
        self.tree.column("date", width=100)
        self.tree.column("status", width=80)
        
        self.tree.pack(fill='both', expand=True)
        
        # Tag Configurations
        self.tree.tag_configure("urgent", background="#ffcccc") # Light Red
        self.tree.tag_configure("warning", background="#ffe5cc") # Light Orange
        self.tree.tag_configure("completed", background="white")
        
        # Bind Double Click
        self.tree.bind("<Double-1>", lambda event: self.edit_selected())
        
        # Buttons
        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill='x', pady=10)
        
        ttk.Button(btn_frame, text="✅ Mark Declared", command=lambda: self.toggle_status(1)).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="⚠️ Mark Pending", command=lambda: self.toggle_status(0)).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="✏️ Edit", command=self.edit_selected).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="📋 Clone Voyage", command=self.clone_selected).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="❌ Delete Entry", command=self.delete_selected).pack(side='right', padx=5)
        ttk.Button(btn_frame, text="🔄 Refresh", command=self.load_voyages).pack(side='right', padx=5)
        
        self.load_voyages()

    def clear_filters(self):
        self.search_var.set("")
        self.port_filter_var.set("All")
        self.show_past_var.set(False)
        self.load_voyages()

    # --- Logic ---

    def clone_selected(self):
        selected = self.tree.selection()
        if not selected:
             messagebox.showwarning("Selection", "Please select a voyage to clone.")
             return
        
        entry_id = selected[0]
        # Identify Voyage ID from entry_id
        df = db_utils.get_voyages_with_details()
        row = df[df['entry_id'] == int(entry_id)]
        if row.empty:
            return
            
        voyage_id = row.iloc[0]['voyage_id']
        vessel_name = row.iloc[0]['vessel_name']
        
        # Popup for Cloning
        popup = tk.Toplevel(self)
        popup.title("Clone Voyage")
        popup.geometry("300x250")
        
        ttk.Label(popup, text=f"Clone Voyage for: {vessel_name}").pack(pady=10)
        
        ttk.Label(popup, text="New Voyage Number:").pack(pady=5)
        voyage_ent = ttk.Entry(popup)
        voyage_ent.pack(pady=5)
        
        ttk.Label(popup, text="New Start Date (First Port):").pack(pady=5)
        date_ent = DateEntry(popup, width=12, background='darkblue', foreground='white', borderwidth=2, date_pattern='yyyy-mm-dd')
        date_ent.pack(pady=5)
        
        def do_clone():
            new_voyage = voyage_ent.get()
            new_date = date_ent.get()
            
            if not new_voyage:
                messagebox.showerror("Error", "Voyage Number is required.")
                return
                
            success, msg = db_utils.duplicate_voyage(int(voyage_id), new_voyage, new_date)
            if success:
                messagebox.showinfo("Success", msg)
                self.load_voyages()
                popup.destroy()
            else:
                messagebox.showerror("Error", msg)
                
        ttk.Button(popup, text="Create Clone", command=do_clone).pack(pady=20)

    def refresh_vessels(self):
        df = db_utils.get_vessels()
        if not df.empty:
            vessels = df['name'].tolist()
            self.vessel_combo['values'] = vessels
            if vessels:
                self.vessel_combo.current(0)
        else:
            self.vessel_combo['values'] = []
            self.vessel_var.set('')
    
    def add_vessel_popup(self):
        popup = tk.Toplevel(self)
        popup.title("Add New Vessel")
        popup.geometry("300x150")
        
        ttk.Label(popup, text="Vessel Name:").pack(pady=5)
        name_ent = ttk.Entry(popup)
        name_ent.pack(pady=5)
        
        ttk.Label(popup, text="IMO Number:").pack(pady=5)
        imo_ent = ttk.Entry(popup)
        imo_ent.pack(pady=5)
        
        def save_vessel():
            name = name_ent.get()
            imo = imo_ent.get()
            if name:
                success, msg = db_utils.add_vessel(name, imo)
                if success:
                    messagebox.showinfo("Success", msg)
                    self.refresh_vessels()
                    popup.destroy()
                else:
                    messagebox.showerror("Error", msg)
            else:
                messagebox.showwarning("Input", "Name is required.")
        
        ttk.Button(popup, text="Save", command=save_vessel).pack(pady=10)

    def delete_vessel_action(self):
        vessel_name = self.vessel_var.get()
        if not vessel_name:
             messagebox.showwarning("Selection", "Please select a vessel to delete.")
             return
             
        if messagebox.askyesno("Confirm Delete", f"Are you sure you want to delete '{vessel_name}'?\nThis might hide past voyages associated with this vessel."):
            success, msg = db_utils.delete_vessel(vessel_name)
            if success:
                messagebox.showinfo("Deleted", msg)
                self.refresh_vessels()
                self.load_voyages() # Refresh list as some might disappear
            else:
                messagebox.showerror("Error", msg)

    def save_data(self):
        vessel_name = self.vessel_var.get()
        voyage_num = self.voyage_num_entry.get()
        service = self.service_entry.get()
        
        if not vessel_name or not voyage_num:
            messagebox.showerror("Error", "Vessel and Voyage Number are required.")
            return 
        # Get Vessel ID
        df = db_utils.get_vessels()
        vessel_id = int(df[df['name'] == vessel_name].iloc[0]['id'])
        
        # Collect Entries
        valid_entries = []
        for p_ent, d_ent in self.entry_widgets:
            port = p_ent.get()
            date_str = d_ent.get()
            if port and date_str:
                try:
                    # Validate Date
                    datetime.strptime(date_str, '%Y-%m-%d')
                    valid_entries.append((port, date_str))
                except ValueError:
                    messagebox.showerror("Error", f"Invalid date format for {port}: {date_str}. Use YYYY-MM-DD")
                    return
        
        if not valid_entries:
            messagebox.showerror("Error", "At least one valid Port and Date entry is required.")
            return
            
        # Save
        voyage_id = db_utils.add_voyage(vessel_id, voyage_num, service)
        for port, date_val in valid_entries:
            db_utils.add_ens_entry(voyage_id, port, date_val)
            
        messagebox.showinfo("Success", "Voyage saved successfully!")
        
        # Clear inputs using delete
        self.voyage_num_entry.delete(0, tk.END)
        for p_ent, d_ent in self.entry_widgets:
            p_ent.delete(0, tk.END)
            d_ent.delete(0, tk.END)
            
        self.load_voyages()

    def load_voyages(self):
        for item in self.tree.get_children():
            self.tree.delete(item)
            
        df = db_utils.get_voyages_with_details()
        if not df.empty:
            show_past = self.show_past_var.get()
            today = datetime.now().date()
            
            # Convert string date to date object for comparison
            # Handle potential parsing errors if format varies? Assuming ISO format YYYY-MM-DD from sqlite
            df['arrival_date_obj'] = pd.to_datetime(df['arrival_date']).dt.date
            
            # --- Apply Filters ---
            
            # 1. Search Text (Vessel Name or Voyage Number)
            search_text = self.search_var.get().lower()
            if search_text:
                # Boolean indexing with OR
                mask = (df['vessel_name'].str.lower().str.contains(search_text, na=False)) | \
                       (df['voyage_number'].str.lower().str.contains(search_text, na=False))
                df = df[mask]
                
            # 2. Port Filter
            port_filter = self.port_filter_var.get()
            if port_filter and port_filter != "All":
                 df = df[df['port'] == port_filter]
            
            # 3. Date Filter (Show Past)
            if not show_past:
                df = df[df['arrival_date_obj'] >= today]
            
            for index, row in df.iterrows():
                status_icon = "✅ YES" if row['is_declared'] else "❌ NO"
                
                # Visual Alerts Logic
                arrival = row['arrival_date_obj']
                is_declared = row['is_declared']
                
                row_tag = "completed"
                if not is_declared:
                    days_remaining = (arrival - today).days
                    if days_remaining <= 2:
                        row_tag = "urgent"
                    elif days_remaining <= 5:
                        row_tag = "warning"
                
                self.tree.insert("", "end", iid=row['entry_id'], values=(
                    row['vessel_name'],
                    row['service_name'],
                    row['voyage_number'], 
                    row['port'], 
                    row['arrival_date'], 
                    status_icon
                ), tags=(row_tag,))

    def toggle_status(self, new_status):
        selected = self.tree.selection()
        if not selected:
            return
        
        entry_id = selected[0]
        db_utils.update_declaration_status(entry_id, new_status)
        self.load_voyages()
        
    def delete_selected(self):
        selected = self.tree.selection()
        if not selected:
            return
        
        count = len(selected)
        if messagebox.askyesno("Confirm", f"Delete {count} selected entr{'ies' if count > 1 else 'y'}?"):
            for item in selected:
                # entry_id is stored in iid (which is item)
                db_utils.delete_entry(item)
            self.load_voyages()

    def edit_selected(self):
        selected = self.tree.selection()
        if not selected:
             return
             
        entry_id = selected[0]
        # Get current values
        item = self.tree.item(entry_id)
        values = item['values']
        # values: vessel, voyage, port, date, status
        
        # Open Popup
        popup = tk.Toplevel(self)
        popup.title("Edit Entry")
        popup.geometry("400x650")
        
        # Details
        ttk.Label(popup, text=f"Edit: {values[0]}").pack(pady=10)
        
        # Service
        ttk.Label(popup, text="Service Name:").pack(pady=2)
        service_ent = ttk.Combobox(popup, values=SERVICE_NAMES)
        service_ent.insert(0, values[1])
        service_ent.pack(pady=2)

        # Voyage Num
        ttk.Label(popup, text="Voyage Number:").pack(pady=2)
        voyage_ent = ttk.Entry(popup)
        voyage_ent.insert(0, values[2]) # Corrected Index
        voyage_ent.pack(pady=2)
        
        # Port
        ttk.Label(popup, text="Port:").pack(pady=2)
        port_ent = ttk.Combobox(popup, values=COMMON_PORTS)
        port_ent.insert(0, values[3]) # Corrected Index
        port_ent.pack(pady=2)
        
        
        # Date
        ttk.Label(popup, text="Arrival Date (YYYY-MM-DD):").pack(pady=2)
        date_ent = DateEntry(popup, width=12, background='darkblue', foreground='white', borderwidth=2, date_pattern='yyyy-mm-dd')
        date_ent.set_date(values[4]) # Corrected Index
        date_ent.pack(pady=2)
        
        # --- File Upload Tracking (West Coast Service) ---
        # values: vessel, service, voyage, port, date, status
        # Service is index 1
        service_name_val = values[1]
        port_name_val = values[3]
        
        uploaded_files_vars = {} # Map code -> BooleanVar
        
        # Fetch current uploaded_files from DB to pre-fill
        # We need to query by entry_id as it's not in the treeview values
        df_full = db_utils.get_voyages_with_details()
        try:
             # entry_id is int, ensure matching type
            entry_row = df_full[df_full['entry_id'] == int(entry_id)]
            current_files_str = entry_row.iloc[0]['uploaded_files'] if not entry_row.empty else ""
            if current_files_str is None: current_files_str = ""
            current_files_list = [x.strip() for x in current_files_str.split(',') if x.strip()]
        except Exception:
            current_files_list = []

        GBLIV_CODES = ["CYLMS", "ILHFA", "ILASH", "TRISK", "EGALY", "ITSAL", "ESCAS", "PTLEI"]
        IEDUB_CODES = ["CYLMS", "ILHFA", "ILASH", "TRISK", "EGALY", "ITSAL", "ESCAS", "PTLEI", "GBLIV"]

        if service_name_val == "West Coast UK" and port_name_val in ["GBLIV", "IEDUB"]:
            frame_files = ttk.LabelFrame(popup, text=f"File Check - {port_name_val}", padding=10)
            frame_files.pack(fill='both', expand=True, padx=10, pady=10)
            
            codes_to_show = GBLIV_CODES if port_name_val == "GBLIV" else IEDUB_CODES
            
            # Create a grid of checkbuttons
            for i, code in enumerate(codes_to_show):
                var = tk.BooleanVar(value=(code in current_files_list))
                uploaded_files_vars[code] = var
                cb = ttk.Checkbutton(frame_files, text=code, variable=var)
                cb.grid(row=i//3, column=i%3, sticky="w", padx=5, pady=2)
        
        def save_edit():
            new_service = service_ent.get()
            new_voyage = voyage_ent.get()
            new_port = port_ent.get()
            new_date = date_ent.get()
            
            # Collect files
            selected_files = []
            for code, var in uploaded_files_vars.items():
                if var.get():
                    selected_files.append(code)
            uploaded_files_str = ",".join(selected_files)
            
            # Using DateEntry, validation is inherent
            
            # Update specific entry
            db_utils.update_ens_entry(entry_id, new_port, new_date, uploaded_files_str)
            
            # Fetch full details to get voyage_id
            df = db_utils.get_voyages_with_details()
            row = df[df['entry_id'] == int(entry_id)]
            if not row.empty:
                voyage_id = row.iloc[0]['voyage_id']
                db_utils.update_voyage(int(voyage_id), new_voyage, new_service)
            
            messagebox.showinfo("Success", "Record Updated")
            self.load_voyages()
            popup.destroy()
            
        ttk.Button(popup, text="Save Changes", command=save_edit).pack(pady=20)

if __name__ == "__main__":
    app = VesselApp()
    app.mainloop()
