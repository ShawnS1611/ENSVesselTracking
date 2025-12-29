@echo off
echo Installing PyInstaller...
pip install pyinstaller

echo Cleaning up previous builds...
taskkill /F /IM "VesselTracking.exe" 2>nul
rmdir /s /q build dist 2>nul
del /q *.spec 2>nul

echo Building executable...
python -m PyInstaller --noconfirm --onefile --windowed --name "VesselTracking" ^
    --hidden-import "babel.numbers" ^
    --hidden-import "pandas" ^
    --hidden-import "tkcalendar" ^
    --hidden-import "openpyxl" ^
    --exclude-module "matplotlib" ^
    --exclude-module "scipy" ^
    --exclude-module "torch" ^
    --exclude-module "tensorflow" ^
    --exclude-module "IPython" ^
    --exclude-module "notebook" ^
    --exclude-module "setuptools" ^
    gui_app.py

echo Copying data files...
copy settings.json dist\settings.json >nul
copy vessels.db dist\vessels.db >nul

echo Build complete. Check the 'dist' folder.
pause
