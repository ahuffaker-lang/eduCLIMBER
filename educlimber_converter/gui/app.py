"""Tkinter shell: pick a file, answer the prompts, review problems, export CSV.

Nothing in here knows about Running Records specifically. The assessment picker,
the prompt widgets and the output file name all come from the converter objects
in :mod:`educlimber_converter.converters`, so a second assessment type appears in
this window as soon as it is registered.
"""

from __future__ import annotations

import os
import traceback
from typing import Dict, List, Optional

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from ..converters import CONVERTERS
from ..core.pipeline import (
    convert_file,
    format_errors,
    save_result,
    suggested_output_path,
    validate_answers,
)
from ..core.spec import CHOICE, ConversionResult, Converter, ConverterError
from ..core.tabular import SourceFileError

APP_TITLE = "eduCLIMBER Assessment Converter"
PAD = 10


class ConverterApp(ttk.Frame):
    def __init__(self, master: tk.Misc) -> None:
        super().__init__(master, padding=PAD)
        self.grid(row=0, column=0, sticky="nsew")
        master.columnconfigure(0, weight=1)
        master.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)

        self.source_path = tk.StringVar(value="")
        self.converter_name = tk.StringVar(value=CONVERTERS[0].display_name)
        self.prompt_vars: Dict[str, tk.StringVar] = {}
        self.result: Optional[ConversionResult] = None

        self._build_assessment_row()
        self._build_file_row()
        self._prompt_frame = ttk.LabelFrame(self, text="Batch settings", padding=PAD)
        self._prompt_frame.grid(row=2, column=0, sticky="ew", pady=(PAD, 0))
        self._prompt_frame.columnconfigure(1, weight=1)
        self._build_status_area()
        self._build_buttons()

        self._render_prompts()
        self._enable_drag_and_drop()
        self._set_status(
            "Choose a source export (.csv or .xlsx), fill in the batch settings, "
            "then click Convert."
        )

    # -- layout ---------------------------------------------------------------

    def _build_assessment_row(self) -> None:
        frame = ttk.LabelFrame(self, text="Assessment", padding=PAD)
        frame.grid(row=0, column=0, sticky="ew")
        frame.columnconfigure(0, weight=1)
        names = [converter.display_name for converter in CONVERTERS]
        picker = ttk.Combobox(
            frame, textvariable=self.converter_name, values=names, state="readonly"
        )
        picker.grid(row=0, column=0, sticky="ew")
        picker.bind("<<ComboboxSelected>>", lambda _event: self._on_converter_changed())
        self._description = ttk.Label(frame, text="", wraplength=560, foreground="#444")
        self._description.grid(row=1, column=0, sticky="w", pady=(6, 0))

    def _build_file_row(self) -> None:
        frame = ttk.LabelFrame(self, text="Source file", padding=PAD)
        frame.grid(row=1, column=0, sticky="ew", pady=(PAD, 0))
        frame.columnconfigure(0, weight=1)
        self._file_label = ttk.Label(
            frame, text="No file selected", wraplength=460, anchor="w"
        )
        self._file_label.grid(row=0, column=0, sticky="ew")
        ttk.Button(frame, text="Choose file...", command=self.choose_file).grid(
            row=0, column=1, padx=(PAD, 0)
        )
        self._drop_hint = ttk.Label(frame, text="", foreground="#444")
        self._drop_hint.grid(row=1, column=0, columnspan=2, sticky="w", pady=(6, 0))

    def _build_status_area(self) -> None:
        frame = ttk.LabelFrame(self, text="Status", padding=PAD)
        frame.grid(row=3, column=0, sticky="nsew", pady=(PAD, 0))
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(0, weight=1)
        self.rowconfigure(3, weight=1)
        self._status = tk.Text(frame, height=10, wrap="word")
        self._status.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(frame, orient="vertical", command=self._status.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self._status.configure(yscrollcommand=scroll.set, state="disabled")

    def _build_buttons(self) -> None:
        frame = ttk.Frame(self)
        frame.grid(row=4, column=0, sticky="ew", pady=(PAD, 0))
        frame.columnconfigure(0, weight=1)
        self._convert_button = ttk.Button(frame, text="Convert", command=self.convert)
        self._convert_button.grid(row=0, column=1)
        self._save_button = ttk.Button(
            frame, text="Save CSV...", command=self.save, state="disabled"
        )
        self._save_button.grid(row=0, column=2, padx=(8, 0))
        ttk.Button(frame, text="Quit", command=self.winfo_toplevel().destroy).grid(
            row=0, column=3, padx=(8, 0)
        )

    # -- converter / prompts --------------------------------------------------

    @property
    def converter(self) -> Converter:
        for converter in CONVERTERS:
            if converter.display_name == self.converter_name.get():
                return converter
        return CONVERTERS[0]

    def _on_converter_changed(self) -> None:
        self._render_prompts()
        self._invalidate_result()

    def _render_prompts(self) -> None:
        for child in self._prompt_frame.winfo_children():
            child.destroy()
        self.prompt_vars = {}
        self._description.configure(text=self.converter.description)

        for row, prompt in enumerate(self.converter.prompts):
            ttk.Label(self._prompt_frame, text=f"{prompt.label}:").grid(
                row=row, column=0, sticky="w", pady=4, padx=(0, 8)
            )
            default = prompt.choices[0] if (prompt.kind == CHOICE and prompt.choices) else ""
            var = tk.StringVar(value=default)
            var.trace_add("write", lambda *_a: self._invalidate_result())
            self.prompt_vars[prompt.key] = var
            if prompt.kind == CHOICE:
                widget = ttk.Combobox(
                    self._prompt_frame,
                    textvariable=var,
                    values=list(prompt.choices),
                    state="readonly",
                )
            else:
                widget = ttk.Entry(self._prompt_frame, textvariable=var)
            widget.grid(row=row, column=1, sticky="ew", pady=4)
            hint = prompt.pattern_help or (
                f"Example: {prompt.placeholder}" if prompt.placeholder else ""
            )
            if hint:
                ttk.Label(self._prompt_frame, text=hint, foreground="#444").grid(
                    row=row, column=2, sticky="w", padx=(8, 0)
                )

    def _answers(self) -> Dict[str, str]:
        return {key: var.get().strip() for key, var in self.prompt_vars.items()}

    # -- actions --------------------------------------------------------------

    def choose_file(self) -> None:
        path = filedialog.askopenfilename(
            title="Select the assessment export",
            filetypes=[
                ("Spreadsheets", "*.csv *.xlsx *.xlsm"),
                ("CSV files", "*.csv"),
                ("Excel files", "*.xlsx *.xlsm"),
                ("All files", "*.*"),
            ],
        )
        if path:
            self.set_source(path)

    def set_source(self, path: str) -> None:
        self.source_path.set(path)
        self._file_label.configure(text=path)
        self._invalidate_result()
        self._set_status(f"Selected: {os.path.basename(path)}\nClick Convert when ready.")

    def convert(self) -> None:
        path = self.source_path.get()
        if not path:
            messagebox.showwarning(APP_TITLE, "Choose a source file first.")
            return
        answers = self._answers()
        problems = validate_answers(self.converter, answers)
        if problems:
            messagebox.showerror(APP_TITLE, "\n".join(problems))
            return

        self._invalidate_result()
        try:
            result = convert_file(self.converter, path, answers)
        except (ConverterError, SourceFileError) as exc:
            self._set_status(f"Could not convert this file.\n\n{exc}")
            messagebox.showerror(APP_TITLE, str(exc))
            return
        except Exception:  # unexpected: show something actionable rather than dying
            detail = traceback.format_exc()
            self._set_status(f"Unexpected error while converting:\n\n{detail}")
            messagebox.showerror(APP_TITLE, "Unexpected error -- see the status box for details.")
            return

        if result.errors:
            summary = (
                f"{len(result.errors)} problem(s) found in "
                f"{os.path.basename(path)} -- nothing was exported.\n"
                "Fix the source file and convert again:\n\n"
                + format_errors(result.errors)
            )
            self._set_status(summary)
            messagebox.showerror(
                APP_TITLE,
                f"{len(result.errors)} row problem(s) found. No file was written -- "
                "see the status box for the full list.",
            )
            return

        self.result = result
        self._save_button.configure(state="normal")
        self._set_status(
            f"Ready: {len(result.rows)} student row(s) converted from "
            f"{os.path.basename(path)}.\nClick 'Save CSV...' to write the eduCLIMBER file."
        )
        self.save()

    def save(self) -> None:
        if not self.result:
            return
        answers = self._answers()
        suggested = suggested_output_path(self.converter, self.source_path.get(), answers)
        path = filedialog.asksaveasfilename(
            title="Save eduCLIMBER CSV",
            defaultextension=".csv",
            initialdir=os.path.dirname(suggested),
            initialfile=os.path.basename(suggested),
            filetypes=[("CSV files", "*.csv"), ("All files", "*.*")],
        )
        if not path:
            return
        try:
            save_result(self.result, path)
        except OSError as exc:
            messagebox.showerror(APP_TITLE, f"Could not save the file:\n{exc}")
            return
        message = f"Converted {len(self.result.rows)} students — saved to\n{path}"
        self._set_status(message)
        messagebox.showinfo(APP_TITLE, message)

    # -- helpers --------------------------------------------------------------

    def _invalidate_result(self) -> None:
        self.result = None
        self._save_button.configure(state="disabled")

    def _set_status(self, text: str) -> None:
        self._status.configure(state="normal")
        self._status.delete("1.0", "end")
        self._status.insert("1.0", text)
        self._status.configure(state="disabled")

    def _enable_drag_and_drop(self) -> None:
        """Wire up file drops when tkinterdnd2 is available; ignore it otherwise."""
        root = self.winfo_toplevel()
        if not hasattr(root, "drop_target_register"):
            self._drop_hint.configure(text="")
            return
        try:
            from tkinterdnd2 import DND_FILES

            root.drop_target_register(DND_FILES)
            root.dnd_bind("<<Drop>>", self._on_drop)
            self._drop_hint.configure(text="You can also drag a file onto this window.")
        except Exception:
            self._drop_hint.configure(text="")

    def _on_drop(self, event) -> None:
        paths = self._parse_drop(event.data)
        if paths:
            self.set_source(paths[0])

    @staticmethod
    def _parse_drop(data: str) -> List[str]:
        """Tk hands over drops as a brace-quoted list when paths contain spaces."""
        paths: List[str] = []
        token = ""
        in_braces = False
        for char in data:
            if char == "{" and not token:
                in_braces = True
            elif char == "}" and in_braces:
                in_braces = False
                paths.append(token)
                token = ""
            elif char == " " and not in_braces:
                if token:
                    paths.append(token)
                token = ""
            else:
                token += char
        if token:
            paths.append(token)
        return paths


def _make_root() -> tk.Tk:
    try:
        from tkinterdnd2 import TkinterDnD

        return TkinterDnD.Tk()
    except Exception:
        return tk.Tk()


def main() -> int:
    root = _make_root()
    root.title(APP_TITLE)
    root.minsize(720, 560)
    try:
        ttk.Style().theme_use("clam")
    except tk.TclError:
        pass
    ConverterApp(root)
    root.mainloop()
    return 0
