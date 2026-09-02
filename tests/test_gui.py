"""GUI smoke test: builds the real window and drives one conversion.

Skipped where tkinter or a display is unavailable (e.g. plain CI containers);
run it under a virtual display with `xvfb-run -a python -m pytest tests`.
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

tk = pytest.importorskip("tkinter")

SAMPLE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "samples",
    "sample_running_records.csv",
)


@pytest.fixture()
def app():
    from educlimber_converter.gui.app import ConverterApp

    try:
        root = tk.Tk()
    except tk.TclError:
        pytest.skip("no display available")
    widget = ConverterApp(root)
    root.update()
    yield widget
    root.destroy()


def test_prompts_come_from_the_converter(app):
    assert set(app.prompt_vars) == {"assessment_window", "school_year"}
    assert app.prompt_vars["assessment_window"].get() == "Trimester 1"


def test_parse_drop_handles_paths_with_spaces(app):
    assert app._parse_drop("{/tmp/a file.csv} /tmp/b.csv") == ["/tmp/a file.csv", "/tmp/b.csv"]


def test_convert_and_save(app, tmp_path, monkeypatch):
    import educlimber_converter.gui.app as gui

    out = str(tmp_path / "out.csv")
    infos, errors = [], []
    monkeypatch.setattr(gui.filedialog, "asksaveasfilename", lambda **k: out)
    monkeypatch.setattr(gui.messagebox, "showinfo", lambda t, m: infos.append(m))
    monkeypatch.setattr(gui.messagebox, "showerror", lambda t, m: errors.append(m))

    app.set_source(SAMPLE)
    app.prompt_vars["school_year"].set("2026-2027")
    app.prompt_vars["assessment_window"].set("Trimester 3")
    app.convert()

    assert not errors
    assert os.path.exists(out)
    assert "Converted 5 students" in infos[0]


def test_row_errors_block_the_export(app, tmp_path, monkeypatch):
    import educlimber_converter.gui.app as gui

    source = tmp_path / "bad.csv"
    source.write_text(
        "Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"
        '"Ray, Jo",10,1,QQ,At Standard\n',
        encoding="utf-8",
    )
    errors = []
    monkeypatch.setattr(gui.messagebox, "showerror", lambda t, m: errors.append(m))

    app.set_source(str(source))
    app.prompt_vars["school_year"].set("2026-2027")
    app.convert()

    assert errors and "1 row problem" in errors[0]
    assert "not in the reading level table" in app._status.get("1.0", "end")
    assert app.result is None
    assert str(app._save_button["state"]) == "disabled"


def test_invalid_school_year_is_caught_before_reading(app, monkeypatch):
    import educlimber_converter.gui.app as gui

    errors = []
    monkeypatch.setattr(gui.messagebox, "showerror", lambda t, m: errors.append(m))
    app.set_source(SAMPLE)
    app.prompt_vars["school_year"].set("26-27")
    app.convert()
    assert errors and "YYYY-YYYY" in errors[0]


TYPO_CSV = (
    "Studnt,Student ID,Grade Level,Readng Levl (A-Z),Proficiency Level\n"
    '"Gomez, Maria",100234,K,Below A,At Standard\n'
)


def _typo_file(tmp_path):
    path = tmp_path / "typo.csv"
    path.write_text(TYPO_CSV, encoding="utf-8")
    return str(path)


def test_dialog_preselects_the_closest_header(app, tmp_path):
    from educlimber_converter.core.mapping import NOT_IN_FILE
    from educlimber_converter.gui.column_dialog import ColumnMatchDialog

    app.set_source(_typo_file(tmp_path))
    app._load()
    dialog = ColumnMatchDialog(app.winfo_toplevel(), app.mapping, "typo.csv")
    try:
        choices = dialog.choices()
        assert choices["student"] == "Studnt"
        assert choices["reading_level"] == "Readng Levl (A-Z)"
        assert choices["grade"] == "Grade Level"  # already auto-matched
        assert NOT_IN_FILE in dialog._choices(app.mapping)
        dialog._on_accept()
        assert dialog.result is True
    finally:
        if dialog.winfo_exists():
            dialog.destroy()
    assert not app.mapping.needs_confirmation


def test_dialog_rejects_one_header_feeding_two_columns(app, tmp_path, monkeypatch):
    from educlimber_converter.gui import column_dialog

    errors = []
    monkeypatch.setattr(column_dialog.messagebox, "showerror", lambda t, m, **k: errors.append(m))

    app.set_source(_typo_file(tmp_path))
    app._load()
    dialog = column_dialog.ColumnMatchDialog(app.winfo_toplevel(), app.mapping, "typo.csv")
    try:
        dialog._vars["reading_level"].set("Studnt")
        dialog._on_accept()
        assert dialog.result is False
        assert errors and "more than one expected column" in errors[0]
        # the mapping is left untouched so the user can fix their pick
        assert app.mapping.get("reading_level").header is None
    finally:
        if dialog.winfo_exists():
            dialog.destroy()


def test_convert_asks_about_misspelled_headers_then_succeeds(app, tmp_path, monkeypatch):
    import educlimber_converter.gui.app as gui

    out = str(tmp_path / "out.csv")
    infos, errors, asked = [], [], []
    monkeypatch.setattr(gui.filedialog, "asksaveasfilename", lambda **k: out)
    monkeypatch.setattr(gui.messagebox, "showinfo", lambda t, m: infos.append(m))
    monkeypatch.setattr(gui.messagebox, "showerror", lambda t, m: errors.append(m))

    def fake_dialog(master, mapping, file_name=""):
        asked.append({m.column.key: m.suggestions[0] for m in mapping.unsettled})
        mapping.apply({key: header for key, header in asked[-1].items()})
        return True

    monkeypatch.setattr(gui, "ask_for_columns", fake_dialog)

    app.set_source(_typo_file(tmp_path))
    app.prompt_vars["school_year"].set("2026-2027")
    app.convert()

    assert asked == [{"student": "Studnt", "reading_level": "Readng Levl (A-Z)"}]
    assert not errors and "Converted 1 students" in infos[0]

    # Converting again reuses the confirmed columns instead of asking twice.
    asked.clear()
    app.convert()
    assert asked == []


def test_cancelling_the_dialog_cancels_the_conversion(app, tmp_path, monkeypatch):
    import educlimber_converter.gui.app as gui

    monkeypatch.setattr(gui, "ask_for_columns", lambda *a, **k: False)
    monkeypatch.setattr(gui.messagebox, "showinfo", lambda t, m: None)
    saved = []
    monkeypatch.setattr(gui.filedialog, "asksaveasfilename", lambda **k: saved.append(1))

    app.set_source(_typo_file(tmp_path))
    app.prompt_vars["school_year"].set("2026-2027")
    app.convert()

    assert not saved and app.result is None
    assert "still need to be matched" in app._status.get("1.0", "end")


def test_match_columns_button_enables_after_loading(app, tmp_path):
    assert str(app._columns_button["state"]) == "disabled"
    app.set_source(_typo_file(tmp_path))
    app._load()
    assert str(app._columns_button["state"]) == "normal"
