import pandas as pd
import sys

file_path = "/Users/hatboy/Projects/mvp-aiHelpStudents/Расписание 1 курс Медицина(НИМО) на весенний семестр 2025-2026гг.xlsx"

try:
    xl = pd.ExcelFile(file_path)
    print(f"Sheet names: {xl.sheet_names}")
    
    for sheet in xl.sheet_names:
        print(f"\n--- Sheet: {sheet} ---")
        df = xl.parse(sheet, nrows=10)
        print(df.to_string())
except Exception as e:
    print(f"Error reading excel: {e}")
