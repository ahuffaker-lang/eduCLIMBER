"""Entry point: GUI by default, ``--cli`` for the command-line front end."""

from __future__ import annotations

import sys


def main() -> int:
    argv = sys.argv[1:]
    if "--cli" in argv or "-h" in argv or "--help" in argv:
        from .cli import main as cli_main

        return cli_main([arg for arg in argv if arg != "--cli"])
    try:
        from .gui.app import main as gui_main
    except ImportError as exc:  # tkinter missing from this Python build
        print(
            "The graphical interface needs Python's tkinter module, which this "
            f"Python does not have ({exc}).\n"
            "Use the command line instead, e.g.:\n"
            '  python -m educlimber_converter --cli export.csv '
            '--assessment-window "Trimester 1" --school-year 2026-2027',
            file=sys.stderr,
        )
        return 3
    return gui_main()


if __name__ == "__main__":
    raise SystemExit(main())
