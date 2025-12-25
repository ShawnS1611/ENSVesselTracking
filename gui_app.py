import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import db_utils
from datetime import datetime
import pandas as pd
from tkcalendar import DateEntry
import xml_utils
import config_manager
import os

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
        self.geometry("1000x700") # Increased size to fit filters
        
        # Init DB
        db_utils.init_db()
        
        # Tabs
        self.notebook = ttk.Notebook(self)
        self.tab_home = ttk.Frame(self.notebook)
        self.tab_input = ttk.Frame(self.notebook)
        self.tab_view = ttk.Frame(self.notebook)
        self.tab_settings = ttk.Frame(self.notebook)
        
        self.notebook.add(self.tab_home, text="🏠 Home")
        self.notebook.add(self.tab_input, text="Input Voyage")
        self.notebook.add(self.tab_view, text="View & Manage")
        self.notebook.add(self.tab_settings, text="Settings")
        self.notebook.pack(expand=True, fill='both')
        
        self.setup_home_tab()
        self.setup_input_tab()
        self.setup_view_tab()
        self.setup_settings_tab()
        
        # Bind tab change to refresh home
        self.notebook.bind("<<NotebookTabChanged>>", self.on_tab_change)

    def on_tab_change(self, event):
        selected_tab = self.notebook.select()
        tab_text = self.notebook.tab(selected_tab, "text")
        if "Home" in tab_text:
            self.refresh_home_tab()

    def setup_home_tab(self):
        # Header
        header = ttk.Frame(self.tab_home, padding=20)
        header.pack(fill='x')
        ttk.Label(header, text="🚢 ENS Vessel Tracking Dashboard", font=("Arial", 16, "bold")).pack(side='left')
        
        # Stats Area
        stats_frame = ttk.Frame(self.tab_home, padding=20)
        stats_frame.pack(fill='x')
        
        self.lbl_stat_voyages = ttk.Label(stats_frame, text="Active Voyages: -", font=("Arial", 12))
        self.lbl_stat_voyages.pack(side='left', padx=20)
        
        self.lbl_stat_upcoming = ttk.Label(stats_frame, text="Arrivals (7 days): -", font=("Arial", 12))
        self.lbl_stat_upcoming.pack(side='left', padx=20)
        
        # Upcoming Table
        content_frame = ttk.LabelFrame(self.tab_home, text="Upcoming Arrivals (Next 7 Days)", padding=10)
        content_frame.pack(fill='both', expand=True, padx=20, pady=10)
        
        cols = ("date", "vessel", "voyage", "port", "service")
        self.home_tree = ttk.Treeview(content_frame, columns=cols, show="headings")
        
        self.home_tree.heading("date", text="Arrival Date")
        self.home_tree.heading("vessel", text="Vessel")
        self.home_tree.heading("voyage", text="Voyage")
        self.home_tree.heading("port", text="Port")
        self.home_tree.heading("service", text="Service")
        
        self.home_tree.column("date", width=100)
        self.home_tree.column("vessel", width=150)
        self.home_tree.column("voyage", width=100)
        self.home_tree.column("port", width=80)
        self.home_tree.column("service", width=150)
        
        self.home_tree.pack(fill='both', expand=True)
        
        # Refresh Button
        ttk.Button(self.tab_home, text="🔄 Refresh Dashboard", command=self.refresh_home_tab).pack(pady=10)

    def refresh_home_tab(self):
        # Clear Tree
        for item in self.home_tree.get_children():
            self.home_tree.delete(item)
            
        # Get Data
        df = db_utils.get_upcoming_entries(7)
        if not df.empty:
            for _, row in df.iterrows():
                self.home_tree.insert("", "end", values=(
                    row['arrival_date'],
                    row['vessel'],
                    row['voyage_number'],
                    row['port'],
                    row['service_name']
                ))
            count_upcoming = len(df)
        else:
            count_upcoming = 0
            
        # Update Stats
        # Active Voyages (all in DB for now, maybe filter by recent later)
        all_voyages = db_utils.get_voyages_with_details()
        if not all_voyages.empty:
            unique_voyages = all_voyages['voyage_number'].nunique()
        else:
            unique_voyages = 0
            
        self.lbl_stat_voyages.config(text=f"Active Voyages: {unique_voyages}")
        self.lbl_stat_upcoming.config(text=f"Arrivals (7 days): {count_upcoming}")
        
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
        
        # Row 1: Search and specific filters
        ttk.Label(filter_frame, text="Search:").grid(row=0, column=0, padx=5, sticky="w")
        self.search_var = tk.StringVar()
        self.search_var.trace("w", lambda name, index, mode: self.load_voyages())
        search_entry = ttk.Entry(filter_frame, textvariable=self.search_var)
        search_entry.grid(row=0, column=1, padx=5, sticky="ew")
        
        ttk.Label(filter_frame, text="Port:").grid(row=0, column=2, padx=5, sticky="w")
        self.port_filter_var = tk.StringVar()
        port_cb = ttk.Combobox(filter_frame, textvariable=self.port_filter_var, values=["All"] + COMMON_PORTS, state="readonly", width=10)
        port_cb.grid(row=0, column=3, padx=5, sticky="ew")
        port_cb.bind("<<ComboboxSelected>>", lambda e: self.load_voyages())
        port_cb.current(0)

        ttk.Label(filter_frame, text="Service:").grid(row=0, column=4, padx=5, sticky="w")
        self.service_filter_var = tk.StringVar()
        service_cb = ttk.Combobox(filter_frame, textvariable=self.service_filter_var, values=["All"] + SERVICE_NAMES, state="readonly", width=15)
        service_cb.grid(row=0, column=5, padx=5, sticky="ew")
        service_cb.bind("<<ComboboxSelected>>", lambda e: self.load_voyages())
        service_cb.current(0)
        
        # Row 2: Toggles and Actions (moved to next row to prevent overflow)
        self.show_past_var = tk.BooleanVar(value=False)
        cb_past = ttk.Checkbutton(filter_frame, text="Show Past Voyages", variable=self.show_past_var, command=self.load_voyages)
        cb_past.grid(row=1, column=0, columnspan=2, padx=5, pady=(5,0), sticky="w")
        
        ttk.Button(filter_frame, text="Clear Filters", command=self.clear_filters).grid(row=1, column=5, padx=5, pady=(5,0), sticky="e")
        
        filter_frame.columnconfigure(1, weight=1)
        
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
        ttk.Button(btn_frame, text="📥 Export Excel", command=self.export_to_excel).pack(side='left', padx=5) # New Button
        ttk.Button(btn_frame, text="❌ Delete Entry", command=self.delete_selected).pack(side='right', padx=5)
        ttk.Button(btn_frame, text="🔄 Refresh", command=self.load_voyages).pack(side='right', padx=5)
        
        self.load_voyages()

    def clear_filters(self):
        self.search_var.set("")
        self.port_filter_var.set("All")
        self.service_filter_var.set("All")
        self.show_past_var.set(False)
        self.load_voyages()

    # --- Logic ---

    def export_to_excel(self):
        # 1. Get filtered data (Re-run filter logic)
        df = db_utils.get_voyages_with_details()
        if df.empty:
            messagebox.showinfo("Export", "No data to export.")
            return

        df['arrival_date_obj'] = pd.to_datetime(df['arrival_date']).dt.date
        
        # Apply Filters
        search_text = self.search_var.get().lower()
        if search_text:
            mask = (df['vessel_name'].str.lower().str.contains(search_text, na=False)) | \
                   (df['voyage_number'].str.lower().str.contains(search_text, na=False))
            df = df[mask]
            
        port_filter = self.port_filter_var.get()
        if port_filter and port_filter != "All":
             df = df[df['port'] == port_filter]

        service_filter = self.service_filter_var.get()
        if service_filter and service_filter != "All":
             df = df[df['service_name'] == service_filter]
        
        show_past = self.show_past_var.get()
        if not show_past:
            today = datetime.now().date()
            df = df[df['arrival_date_obj'] >= today]
            
        if df.empty:
            messagebox.showinfo("Export", "No matching data to export.")
            return
            
        # 2. Ask for Save Location
        filename = tk.filedialog.asksaveasfilename(
            defaultextension=".xlsx",
            filetypes=[("Excel Files", "*.xlsx"), ("All Files", "*.*")],
            title="Export to Excel"
        )
        
        if filename:
            try:
                # Clean up columns for export
                export_df = df[['vessel_name', 'voyage_number', 'service_name', 'port', 'arrival_date', 'is_declared', 'uploaded_files']].copy()
                export_df.columns = ['Vessel', 'Voyage', 'Service', 'Port', 'Arrival Date', 'Declared', 'Files']
                export_df['Declared'] = export_df['Declared'].apply(lambda x: "Yes" if x else "No")
                
                export_df.to_excel(filename, index=False)
                messagebox.showinfo("Success", f"Data exported to {filename}")
            except Exception as e:
                messagebox.showerror("Export Error", f"Failed to export: {e}") 

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

            # 3. Service Filter
            service_filter = self.service_filter_var.get()
            if service_filter and service_filter != "All":
                 df = df[df['service_name'] == service_filter]
            
            # 4. Date Filter (Show Past)
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

        # --- XML Batch Update Section (Embedded) ---
        ttk.Separator(popup, orient='horizontal').pack(fill='x', pady=10)
        ttk.Label(popup, text="Advanced: Batch Update XMLs", font=("Arial", 10, "bold")).pack(pady=5)
        
        # Calculate Default Path
        voyage_val_for_path = values[2] # Use the voyage from the tree (or entry, but entry might be edited)
        # Assuming we want based on what is currently saved/selected
        default_path = os.path.join(r"C:\Users\shawn\Documents\Coding\Python\XMLs", str(voyage_val_for_path))
        
        # UI Elements
        path_frame = ttk.Frame(popup)
        path_frame.pack(fill='x', padx=10)
        
        ttk.Label(path_frame, text="XML Directory:").pack(anchor='w')
        
        path_var = tk.StringVar(value=default_path)
        path_ent = ttk.Entry(path_frame, textvariable=path_var)
        path_ent.pack(fill='x', pady=2)
        path_ent.config(state='disabled') # Default to disabled
        
        def toggle_path_edit():
            if path_edit_var.get():
                path_ent.config(state='normal')
            else:
                path_ent.config(state='disabled')
                
        path_edit_var = tk.BooleanVar(value=False)
        chk_edit = ttk.Checkbutton(path_frame, text="Edit Path", variable=path_edit_var, command=toggle_path_edit)
        chk_edit.pack(anchor='w')
        
        def run_embedded_xml_update():
            # 1. Gather Data (from the EDIT fields, so it matches what they are about to save/have saved)
            curr_voyage = voyage_ent.get()
            curr_port = port_ent.get()
            curr_date = date_ent.get()
            curr_service = service_ent.get() # Not used for update but context
            vessel_name = values[0] # From original selection (read-only in this popup anyway)

            # Lookup IMO
            df_vessels = db_utils.get_vessels()
            try:
                imo = df_vessels[df_vessels['name'] == vessel_name].iloc[0]['imo_number']
            except IndexError:
                imo = ""
            
            target_dir = path_var.get()
            
            # Validation
            if not os.path.exists(target_dir):
                if messagebox.askyesno("Directory Missing", f"Directory not found:\n{target_dir}\n\nContinue anyway (will look for files)?"):
                     pass 
                else: 
                     return

            # Subdirectory Selection
            subdirs = [d for d in os.listdir(target_dir) if os.path.isdir(os.path.join(target_dir, d))]
            
            # If no subdirectories, fall back to updating the root folder recursively
            if not subdirs:
                if messagebox.askyesno("Confirm Update", f"No subdirectories found in:\n{target_dir}\n\nUpdate all XML files in this directory recursively?\n\nValues:\nVoyage: {curr_voyage}\nIMO: {imo}\nPort: {curr_port}\nDate: {curr_date}"):
                    count, errors = xml_utils.update_xml_directory(target_dir, curr_voyage, imo, curr_port, curr_date)
                    _show_results(count, errors)
                return

            # Show Selection Popup
            sel_popup = tk.Toplevel(xml_pop_frame) # Using the frame or popup as master
            sel_popup.title("Select Subdirectories")
            sel_popup.geometry("400x500")
            
            ttk.Label(sel_popup, text="Select folders to update:", font=("Arial", 10, "bold")).pack(pady=10)
            
            list_frame = ttk.Frame(sel_popup)
            list_frame.pack(fill='both', expand=True, padx=10)
            
            scrollbar = ttk.Scrollbar(list_frame)
            scrollbar.pack(side='right', fill='y')
            
            lb = tk.Listbox(list_frame, selectmode='multiple', yscrollcommand=scrollbar.set, height=15)
            lb.pack(side='left', fill='both', expand=True)
            scrollbar.config(command=lb.yview)
            
            for d in subdirs:
                lb.insert(tk.END, d)
                
            # Select All by default
            lb.select_set(0, tk.END)
            
            btn_frame = ttk.Frame(sel_popup)
            btn_frame.pack(fill='x', pady=5)
            
            def select_all(): lb.select_set(0, tk.END)
            def select_none(): lb.selection_clear(0, tk.END)
            
            ttk.Button(btn_frame, text="Select All", command=select_all).pack(side='left', padx=10)
            ttk.Button(btn_frame, text="Clear Selection", command=select_none).pack(side='left', padx=10)
            
            def confirm_update():
                selected_indices = lb.curselection()
                if not selected_indices:
                    messagebox.showwarning("Selection", "No folders selected.", parent=sel_popup)
                    return
                
                selected_folders = [subdirs[i] for i in selected_indices]
                
                if not messagebox.askyesno("Confirm", f"Update {len(selected_folders)} folders?\n\nValues:\nVoyage: {curr_voyage}\nIMO: {imo}\nDate: {curr_date}", parent=sel_popup):
                    return
                
                total_count = 0
                all_errors = []
                
                for folder in selected_folders:
                    full_path = os.path.join(target_dir, folder)
                    count, errors = xml_utils.update_xml_directory(full_path, curr_voyage, imo, curr_port, curr_date)
                    total_count += count
                    all_errors.extend(errors)
                    
                sel_popup.destroy()
                _show_results(total_count, all_errors)

            ttk.Button(sel_popup, text="✅ Confirm & Update", command=confirm_update).pack(pady=15, fill='x', padx=20)

        def _show_results(count, errors):
            msg = f"Updated {count} files."
            if errors:
                msg += f"\n\nErrors ({len(errors)}): check console/log."
                messagebox.showwarning("Update Result", msg)
            else:
                messagebox.showinfo("Update Result", msg)
        
        # Keep reference to popup for parenting
        xml_pop_frame = path_frame 

        ttk.Button(popup, text="🚀 Run XML Update Now", command=run_embedded_xml_update).pack(pady=10)

    def setup_settings_tab(self):
        frame = ttk.Frame(self.tab_settings, padding=20)
        frame.pack(fill='both', expand=True)

        ttk.Label(frame, text="Port Mappings (Config)", font=("Arial", 12, "bold")).pack(anchor='w', pady=(0, 10))
        
        # Splitter or columns
        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill='x', pady=5)
        
        self.settings_tree = ttk.Treeview(frame, columns=("port", "ref"), show="headings", height=15)
        self.settings_tree.heading("port", text="Port Code")
        self.settings_tree.heading("ref", text="Ref Num (Customs Office)")
        self.settings_tree.column("port", width=150)
        self.settings_tree.column("ref", width=250)
        self.settings_tree.pack(fill='both', expand=True)
        
        # Load Data
        self.refresh_settings_tree()
        
        # Controls
        ttk.Button(btn_frame, text="➕ Add Mapping", command=self.add_mapping_popup).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="✏️ Edit", command=self.edit_mapping_popup).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="❌ Delete", command=self.delete_mapping).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="🔄 Reload from File", command=self.refresh_settings_tree).pack(side='right', padx=5)

    def refresh_settings_tree(self):
        for item in self.settings_tree.get_children():
            self.settings_tree.delete(item)
        
        settings = config_manager.load_settings()
        mappings = settings.get("port_mappings", {})
        
        for port, ref in mappings.items():
            self.settings_tree.insert("", "end", values=(port, ref))
            
    def save_mapping_changes(self, new_mappings):
        settings = config_manager.load_settings()
        settings["port_mappings"] = new_mappings
        if config_manager.save_settings(settings):
             self.refresh_settings_tree()
             messagebox.showinfo("Success", "Settings saved.")
        else:
             messagebox.showerror("Error", "Failed to save settings.")

    def add_mapping_popup(self):
         self.mapping_popup("Add Mapping")

    def edit_mapping_popup(self):
        selected = self.settings_tree.selection()
        if not selected: return
        item = self.settings_tree.item(selected[0])
        self.mapping_popup("Edit Mapping", item['values'][0], item['values'][1])

    def mapping_popup(self, title, port="", ref=""):
        win = tk.Toplevel(self)
        win.title(title)
        win.geometry("300x150")
        
        ttk.Label(win, text="Port Code:").pack(pady=5)
        ent_port = ttk.Entry(win)
        ent_port.insert(0, port)
        ent_port.pack()
        if title == "Edit Mapping": ent_port.config(state='disabled') # Key usually shouldn't change easily or it's a delete/add
        
        ttk.Label(win, text="Ref Num:").pack(pady=5)
        ent_ref = ttk.Entry(win)
        ent_ref.insert(0, ref)
        ent_ref.pack()
        
        def save():
            p = ent_port.get().strip()
            r = ent_ref.get().strip()
            if not p or not r:
                messagebox.showwarning("Input", "Both fields required.")
                return
            
            settings = config_manager.load_settings()
            mappings = settings.get("port_mappings", {})
            mappings[p] = r
            
            self.save_mapping_changes(mappings)
            win.destroy()
            
        ttk.Button(win, text="Save", command=save).pack(pady=10)

    def delete_mapping(self):
        selected = self.settings_tree.selection()
        if not selected: return
        port = self.settings_tree.item(selected[0])['values'][0]
        
        if messagebox.askyesno("Confirm", f"Delete mapping for {port}?"):
            settings = config_manager.load_settings()
            mappings = settings.get("port_mappings", {})
            if port in mappings:
                del mappings[port]
                self.save_mapping_changes(mappings)

if __name__ == "__main__":
    app = VesselApp()
    app.mainloop()
