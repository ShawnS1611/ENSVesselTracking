import pypdf
import os

pdf_path = os.path.join("Schedules", "AdriaticWeek51.pdf")

try:
    reader = pypdf.PdfReader(pdf_path)
    print(f"Number of pages: {len(reader.pages)}")
    for i, page in enumerate(reader.pages):
        print(f"--- Page {i+1} ---")
        print(page.extract_text())
except Exception as e:
    print(f"Error reading PDF: {e}")
