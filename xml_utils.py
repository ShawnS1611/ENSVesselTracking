import os
import xml.etree.ElementTree as ET
from datetime import datetime
import config_manager

def update_xml_directory(base_dir, voyage_num, imo, port, arrival_date_str):
    """
    Recursively updates all XML files in the directory.
    arrival_date_str: "YYYY-MM-DD"
    """
    updated_count = 0
    errors = []

    # Format Date for XML: YYYYMMDDHHmm (Sample: 202512110000)
    # We append 0000 for midnight as requested
    try:
        dt = datetime.strptime(arrival_date_str, '%Y-%m-%d')
        formatted_date = dt.strftime('%Y%m%d') + "0000"
    except ValueError:
        return 0, [f"Invalid date format: {arrival_date_str}"]

    for root_dir, dirs, files in os.walk(base_dir):
        for file in files:
            if file.lower().endswith('.xml'):
                full_path = os.path.join(root_dir, file)
                try:
                    success = update_xml_file(full_path, voyage_num, imo, port, formatted_date)
                    if success:
                        updated_count += 1
                except Exception as e:
                    errors.append(f"{file}: {str(e)}")
    
    return updated_count, errors

def update_xml_file(file_path, voyage_num, imo, port, formatted_date):
    ET.register_namespace('', "http://www.ksdsoftware.com/Schema/ICS/EntrySummaryDeclaration")
    
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Namespace map
        ns = {'ns': 'http://www.ksdsoftware.com/Schema/ICS/EntrySummaryDeclaration'}
        
        # Helper to find and update
        def update_val(xpath, value):
            node = root.find(xpath, ns)
            if node is not None:
                node.text = value
                return True
            return False

        def ensure_child_node(parent_xpath, child_tag, default_value):
            # Finds parent, checks for child. If missing, adds it.
            parent = root.find(parent_xpath, ns)
            if parent is None:
                return # Parent missing, can't add child
            
            # Check for existing child with namespace
            child = parent.find(f"ns:{child_tag}", ns)
            if child is None:
                new_node = ET.Element(f"{{{ns['ns']}}}{child_tag}") # Use full QName
                new_node.text = default_value
                parent.append(new_node)

        # 1. Update ConveyanceRefNum (Voyage Number)
        update_val(".//ns:EntrySummaryDeclaration/ns:ConveyanceRefNum", voyage_num)
        
        # 2. Update IdeOfMeaOfTraCro (IMO Number)
        update_val(".//ns:EntrySummaryDeclaration/ns:IdeOfMeaOfTraCro", imo)
        
        # 3. Update DeclPlace (Port) AND RefNum
        update_val(".//ns:EntrySummaryDeclaration/ns:DeclPlace", port)
        
        # Lookup RefNum
        ref_num = config_manager.get_ref_num(port)
        if ref_num:
             update_val(".//ns:EntrySummaryDeclaration/ns:CustOfficeOfFirstEntry/ns:RefNum", ref_num)
        
        # 4. Update ExpectedDateTimeOfArrival
        update_val(".//ns:EntrySummaryDeclaration/ns:CustOfficeOfFirstEntry/ns:ExpectedDateTimeOfArrival", formatted_date)

        # 5. Ensure Consignee/Consignor have Number tag
        ensure_child_node(".//ns:EntrySummaryDeclaration/ns:Consignor", "Number", "N/A")
        ensure_child_node(".//ns:EntrySummaryDeclaration/ns:Consignee", "Number", "N/A")

        # 6. Conditionally Update LodgingPerson and Carrier TINs
        # Rule: If DeclPlace is GBLIV or GBFXT -> GB243408284000
        #       Else -> XI243408284000
        gb_ports = ["GBLIV", "GBFXT"]
        if port.upper() in gb_ports:
            tin_value = "GB243408284000"
        else:
            tin_value = "XI243408284000"
            
        update_val(".//ns:EntrySummaryDeclaration/ns:LodgingPerson/ns:TIN", tin_value)
        update_val(".//ns:EntrySummaryDeclaration/ns:Carrier/ns:TIN", tin_value)

        tree.write(file_path, encoding='utf-8', xml_declaration=True)
        return True
    
    except ET.ParseError:
        print(f"Skipping invalid XML: {file_path}")
        return False
