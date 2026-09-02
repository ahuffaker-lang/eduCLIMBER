"""Launcher used both for `python run_app.py` and as the PyInstaller entry point."""

import sys

from educlimber_converter.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
