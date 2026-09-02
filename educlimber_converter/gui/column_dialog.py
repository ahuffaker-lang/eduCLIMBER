"""Modal dialog: 'which column in your file is this?'

Shown when a header is misspelled, renamed, or missing -- and on demand from the
main window, so column choices can be reviewed before every conversion.
"""

from __future__ import annotations

from typing import Dict, List, Optional

import tkinter as tk
from tkinter import messagebox, ttk

from ..core.mapping import NOT_IN_FILE, ColumnMapping

PAD = 10


class ColumnMatchDialog(tk.Toplevel):
    """Ask the user to match expected columns to the headers in their file.

    ``result`` is ``True`` when the user accepted the choices (already applied to
    the mapping), ``False`` when they cancelled.
    """

    def __init__(self, master: tk.Misc, mapping: ColumnMapping, file_name: str = "") -> None:
        super().__init__(master)
        self.mapping = mapping
        self.result = False
        self._vars: Dict[str, tk.StringVar] = {}

        self.title("Match columns")
        self.transient(master)
        self.resizable(True, False)

        frame = ttk.Frame(self, padding=PAD)
        frame.grid(row=0, column=0, sticky="nsew")
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)
        frame.columnconfigure(1, weight=1)

        unmatched = [match.column.label for match in mapping.unsettled]
        if unmatched:
            headline = (
                "Some columns could not be matched automatically"
                + (f" in {file_name}" if file_name else "")
                + ":\n"
                + ", ".join(unmatched)
                + "\n\nPick the column from your file that holds each one. "
                "The closest match is pre-selected -- change it if it's wrong."
            )
        else:
            headline = (
                "Every expected column was matched automatically. "
                "Change any of them here if a column was matched to the wrong header."
            )
        ttk.Label(frame, text=headline, wraplength=620, justify="left").grid(
            row=0, column=0, columnspan=3, sticky="w", pady=(0, PAD)
        )

        ttk.Label(frame, text="Expected column", font=("", 9, "bold")).grid(
            row=1, column=0, sticky="w"
        )
        ttk.Label(frame, text="Column in your file", font=("", 9, "bold")).grid(
            row=1, column=1, sticky="w", padx=(PAD, 0)
        )

        for offset, match in enumerate(mapping.matches):
            row = offset + 2
            label = match.column.label + ("" if match.column.required else "  (optional)")
            ttk.Label(frame, text=label).grid(row=row, column=0, sticky="w", pady=3)

            choices = self._choices(mapping)
            preselected = match.header or (match.suggestions[0] if match.suggestions else "")
            var = tk.StringVar(value=preselected or NOT_IN_FILE)
            self._vars[match.column.key] = var
            box = ttk.Combobox(
                frame, textvariable=var, values=choices, state="readonly", width=34
            )
            box.grid(row=row, column=1, sticky="ew", padx=(PAD, 0), pady=3)

            note = "" if match.settled else "needs checking"
            if match.column.example:
                note = (note + " · " if note else "") + f"e.g. {match.column.example}"
            ttk.Label(frame, text=note, foreground="#444").grid(
                row=row, column=2, sticky="w", padx=(PAD, 0)
            )

        buttons = ttk.Frame(frame)
        buttons.grid(row=len(mapping.matches) + 2, column=0, columnspan=3, sticky="e", pady=(PAD, 0))
        ttk.Button(buttons, text="Cancel", command=self._on_cancel).grid(row=0, column=0)
        ttk.Button(buttons, text="Use these columns", command=self._on_accept).grid(
            row=0, column=1, padx=(8, 0)
        )

        self.protocol("WM_DELETE_WINDOW", self._on_cancel)
        self.bind("<Escape>", lambda _event: self._on_cancel())
        self._center_on(master)

    def _center_on(self, master: tk.Misc) -> None:
        self.update_idletasks()
        try:
            x = master.winfo_rootx() + max(0, (master.winfo_width() - self.winfo_width()) // 2)
            y = master.winfo_rooty() + 60
            self.geometry(f"+{max(0, x)}+{max(0, y)}")
        except tk.TclError:  # no window manager (headless test runs)
            pass

    @staticmethod
    def _choices(mapping: ColumnMapping) -> List[str]:
        return list(mapping.headers) + [NOT_IN_FILE]

    def choices(self) -> Dict[str, Optional[str]]:
        return {
            key: (None if var.get() == NOT_IN_FILE else var.get())
            for key, var in self._vars.items()
        }

    def _on_accept(self) -> None:
        snapshot = [(match.header, match.confirmed) for match in self.mapping.matches]
        self.mapping.apply(self.choices())
        problems = self.mapping.problems()
        if problems:
            # Roll back so the mapping is untouched while the user fixes the picks.
            for match, (header, confirmed) in zip(self.mapping.matches, snapshot):
                match.header, match.confirmed = header, confirmed
            messagebox.showerror("Match columns", "\n".join(problems), parent=self)
            return
        self.result = True
        self.destroy()

    def _on_cancel(self) -> None:
        self.result = False
        self.destroy()


def ask_for_columns(master: tk.Misc, mapping: ColumnMapping, file_name: str = "") -> bool:
    """Show the dialog and block until the user answers. True when accepted."""
    dialog = ColumnMatchDialog(master, mapping, file_name)
    dialog.grab_set()
    master.wait_window(dialog)
    return dialog.result
