# PyInstaller spec: builds a one-file, windowed executable.
#   pyinstaller educlimber_converter.spec
# Output: dist/eduCLIMBER-Converter(.exe)

block_cipher = None

a = Analysis(
    ["run_app.py"],
    pathex=["."],
    binaries=[],
    # The reading-level lookup table ships inside the bundle; running_records.py
    # resolves it through sys._MEIPASS at runtime.
    datas=[("educlimber_converter/data/Data_Table.csv", "educlimber_converter/data")],
    hiddenimports=["openpyxl"],
    hookspath=[],
    runtime_hooks=[],
    excludes=["numpy", "pandas", "matplotlib"],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="eduCLIMBER-Converter",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    runtime_tmpdir=None,
    console=False,  # windowed app -- no terminal behind the GUI
)
