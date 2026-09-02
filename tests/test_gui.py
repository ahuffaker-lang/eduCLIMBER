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
