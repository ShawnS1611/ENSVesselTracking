# ENS Vessel Tracking & Todo List

## Overview
This application is designed to manage and track vessel voyages, port calls, and Entry Summary Declaration (ENS) statuses. It provides tools for logistics coordinators to ensure all necessary declarations are made on time.

The project features two interfaces:
1.  **Desktop GUI (Tkinter)**: A full-featured desktop application for managing voyages, vessel data, and performing batch XML updates for port systems.
2.  **Web Dashboard (Streamlit)**: A lightweight web interface for quick viewing, status updates, and simple data entry.

## Features

### 🚢 Vessel & Voyage Management
*   **Database**: Centralized SQLite database (`vessels.db`) storing vessels, voyages, and port calls.
*   **Input**: Easily add new vessels and create voyages with multiple port calls.
*   **Services**: predefined services (e.g., "Adriatic", "West Coast UK").

### ✅ Declaration Tracking
*   **Status Toggle**: Mark port calls as "Declared" or "Pending".
*   **Visual Alerts**: Color-coded rows in the dashboard highlight upcoming or urgent undeclared arrivals (Next 2 days = Red/Urgent).
*   **Filtering**: Filter voyages by Port, Service, Date, or Search by vessel name/voyage number.

### 📄 Advanced Tools (Desktop App)
*   **XML Batch Update**: Automatically update XML files in a specific directory with the current voyage details (Voyage Number, Date, Port). Useful for updating ICS/Customs files.
*   **File Checklist**: Special tracking for the "West Coast UK" service to ensure specific files (e.g., `CYLMS`, `GBLIV`) are uploaded.
*   **Export**: Export the current filtered view to Excel.

## Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/ShawnS1611/ENSVesselTracking.git
    cd ENSVesselTracking
    ```

2.  **Install Dependencies**:
    It is recommended to use a virtual environment.
    ```bash
    pip install -r requirements.txt
    ```

## Usage

### Running the Desktop App
The desktop application is the primary tool for detailed management.
```bash
python gui_app.py
```
*   **Tabs**:
    *   **Home**: Dashboard with upcoming arrivals stats.
    *   **Input Voyage**: Form to create new records.
    *   **View & Manage**: Main table to filter, search, edit, and update statuses. Double-click a row to Edit or run XML updates.

### Running the Web Dashboard
The web app is great for quick status checks or for other team members to view data.
```bash
streamlit run app.py
```

## Configuration

### settings.json
The application uses a `settings.json` file to map Port Codes (e.g., `CYLMS`) to their corresponding Reference Numbers (e.g., `CY000510`) used in XML generation.
You can edit this file to add or modify port mappings as needed.
```json
{
    "port_mappings": {
        "CYLMS": "CY000510",
        ...
    }
}
```

## Building the Executable
To package the desktop application as a standalone `.exe` file for Windows:

1.  Run the build script:
    ```cmd
    build_exe.bat
    ```
2.  The executable will be created in the `dist/` folder.

## Project Structure
*   `gui_app.py`: Main source code for the Desktop GUI.
*   `app.py`: Source code for the Streamlit Web App.
*   `db_utils.py`: Database connection and helper functions.
*   `xml_utils.py`: Logic for parsing and updating XML files.
*   `vessels.db`: SQLite database file (created automatically on first run).
*   `requirements.txt`: Python package dependencies.
