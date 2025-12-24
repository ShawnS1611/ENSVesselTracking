from datetime import date, timedelta

def get_tag(arrival_date, is_declared):
    today = date.today()
    if is_declared:
        return "completed"
    
    days_remaining = (arrival_date - today).days
    if days_remaining <= 2:
        return "urgent"
    elif days_remaining <= 5:
        return "warning"
    else:
        return "completed"

def test_alerts():
    today = date.today()
    
    # Case 1: Urgent (Tomorrow)
    d1 = today + timedelta(days=1)
    tag = get_tag(d1, False)
    print(f"Arrival {d1} (1 day): Tag '{tag}' -> Expected 'urgent'")
    assert tag == "urgent"
    
    # Case 2: Urgent (Today)
    d2 = today
    tag = get_tag(d2, False)
    print(f"Arrival {d2} (0 days): Tag '{tag}' -> Expected 'urgent'")
    assert tag == "urgent"
    
    # Case 3: Warning (4 days)
    d3 = today + timedelta(days=4)
    tag = get_tag(d3, False)
    print(f"Arrival {d3} (4 days): Tag '{tag}' -> Expected 'warning'")
    assert tag == "warning"
    
    # Case 4: Fine (6 days)
    d4 = today + timedelta(days=6)
    tag = get_tag(d4, False)
    print(f"Arrival {d4} (6 days): Tag '{tag}' -> Expected 'completed'")
    assert tag == "completed"
    
    # Case 5: Declared (even if urgent)
    tag = get_tag(d1, True)
    print(f"Arrival {d1} (Declared): Tag '{tag}' -> Expected 'completed'")
    assert tag == "completed"
    
    print("Alert Logic PASSED")

if __name__ == "__main__":
    test_alerts()
