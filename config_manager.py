import json
import os

SETTINGS_FILE = "settings.json"

def load_settings():
    """Loads settings from JSON file. Returns default structure if missing."""
    if not os.path.exists(SETTINGS_FILE):
        return {"port_mappings": {}}
    
    try:
        with open(SETTINGS_FILE, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        return {"port_mappings": {}}

def save_settings(settings):
    """Saves dictionary to JSON file."""
    try:
        with open(SETTINGS_FILE, 'w') as f:
            json.dump(settings, f, indent=4)
        return True
    except Exception as e:
        print(f"Error saving settings: {e}")
        return False

def get_ref_num(port_code):
    """Helper to get RefNum for a Port Code."""
    settings = load_settings()
    mappings = settings.get("port_mappings", {})
    return mappings.get(port_code, "")
