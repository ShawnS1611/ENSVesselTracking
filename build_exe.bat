@echo off
echo Installing PyInstaller...
pip install pyinstaller

echo Cleaning up previous builds...
rmdir /s /q build dist 2>nul
del /q *.spec 2>nul

echo Building executable...
pyinstaller --noconfirm --onefile --windowed --name "VesselTracking" ^
    --hidden-import "babel.numbers" ^
    gui_app.py

echo Build complete.
pause
