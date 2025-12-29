# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['gui_app.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['babel.numbers', 'pandas', 'tkcalendar', 'openpyxl'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['matplotlib', 'scipy', 'torch', 'tensorflow', 'IPython', 'notebook', 'setuptools'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='VesselTracking',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
