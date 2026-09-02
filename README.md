# eduCLIMBER Assessment Converter

A small desktop app that reshapes a **Running Records** reading-assessment export
into the 15-column CSV that eduCLIMBER's upload expects.

Pick the export → choose the assessment window and school year → the app validates
every row and writes the eduCLIMBER file.

## Running it

**From a packaged executable** (what most users get): double-click
`eduCLIMBER-Converter` — no Python install needed.

**From source:**

```bash
python run_app.py                     # opens the window
pip install -r requirements.txt       # only needed to read .xlsx files
```

There is also a command line for scripted runs:

```bash
python run_app.py --cli export.xlsx \
    --assessment-window "Trimester 1" --school-year 2026-2027 [--out result.csv]
```

Exit codes: `0` success, `1` row-level problems (nothing written), `2` file or
prompt problem.

## Source file

CSV or Excel, with these columns (header text is matched case-insensitively and
ignoring punctuation/spacing, so `reading_level` or `READING LEVEL (A-Z)` are fine):

| Column | Notes |
|---|---|
| `Student` | `"Last, First"` |
| `Student ID` | required |
| `Grade Level` | `K`, `1` … `8` |
| `Reading Level (A-Z)` | `Below A`, `A`–`Z` |
| `Proficiency Level` | passed through as-is |

### When a column is misnamed or misspelled

The app never guesses at a header it doesn't recognize. If a column is misspelled
(`Readng Levl (A-Z)`) or renamed (`Rdg Level A-Z`), a **Match columns** dialog opens
and asks which column in your file holds each expected one, with the closest header
pre-selected — accept it or pick another from the dropdown. Choose
`— not in this file —` for a column that genuinely isn't there (only allowed for
optional columns). One file column can't be assigned to two expected columns.

Your choices are remembered for that file, so re-converting after changing the
window or school year doesn't ask again. **Match columns...** in the main window
opens the same dialog any time, including when everything matched automatically —
useful for checking a column wasn't matched to the wrong header.

On the command line, unmatched columns are prompted for interactively; in a script
(or with `--no-prompt`) the run fails with the closest-match suggestion and you
supply the answer with repeatable `--map` flags:

```bash
python run_app.py --cli export.csv --assessment-window "Trimester 1" \
    --school-year 2026-2027 \
    --map student=Studnt --map "reading_level=Readng Levl (A-Z)"
```

## What it produces

15 columns, in this exact order:

```
Assessment Group, Assessment Name, Assessment Window, School Year, Student ID,
Student First Name, Student Middle Initial, Student Last Name, Date of Birth,
Student Grade Level, Score Detail 2, Reading Level, Score Detail 1,
Proficiency Level, Score
```

- `Assessment Group` is always `Running Records`; `Assessment Name` is always
  `Independent Reading Level`.
- `Student Middle Initial` and `Date of Birth` are always blank.
- `Score Detail 2` / `Reading Level` hold the same value, and so do
  `Score Detail 1` / `Proficiency Level`. That duplication is what the eduCLIMBER
  import format wants — it is not a bug.
- `Score` comes from `educlimber_converter/data/Data_Table.csv`
  (`Below A` → 1, `A` → 2, … `Z` → 27, `Z+` → 28, `MAX` → 29).

Default file name: `Running_Records_<Window>_<SchoolYear>_educlimber.csv`, saved
wherever you choose (the source folder is suggested). Written as plain UTF-8 with
no byte-order mark, so eduCLIMBER reads the first header cleanly.

## Validation

The conversion is all-or-nothing: if any row has a problem, **no file is written**
and the app lists every offending row by its spreadsheet row number, so you can fix
the source and re-run. Rows are flagged for an unrecognized or blank reading level,
a blank Student ID, and a student name that isn't in `Last, First` form. An invalid school
year stops the run before any row is read, and an unmatched column is asked about
rather than failing. Completely
blank rows are skipped rather than flagged.

School year must match `YYYY-YYYY` exactly — no spaces.

## Building the executable

```bash
pip install -r requirements-dev.txt
pyinstaller educlimber_converter.spec      # -> dist/eduCLIMBER-Converter
```

PyInstaller does not cross-compile: build on Windows for a `.exe`, on macOS for a
Mac build. `Data_Table.csv` is bundled in, and the app finds it via `sys._MEIPASS`.

## Tests

```bash
pip install -r requirements-dev.txt
python -m pytest tests -q          # GUI tests skip without a display
xvfb-run -a python -m pytest tests -q   # Linux: include the GUI tests
```

## Adding another assessment type

The shell (file picking, prompts, validation display, CSV export) is
assessment-agnostic; everything specific to Running Records lives in one module.

```
educlimber_converter/
  core/spec.py       PromptField / ConversionResult / the Converter protocol
  core/tabular.py    read CSV+Excel, loose header matching, write CSV
  core/mapping.py    match expected columns to real headers, rank suggestions
  core/pipeline.py   read -> validate -> map -> save
  converters/
    running_records.py   source columns, lookup table, field mapping, prompts
  gui/app.py         Tkinter window, built from whatever converters are registered
  gui/column_dialog.py  "which column is this?" dialog for unmatched headers
  cli.py             same pipeline, no GUI
  data/Data_Table.csv
```

To add one: write a sibling module in `converters/` with `key`, `display_name`,
`description`, `prompts`, `source_columns`, `output_columns`,
`convert(table, answers, columns)` and `default_output_name(answers)`, then add it
to `CONVERTERS` in `converters/__init__.py`. It shows up in the app's assessment
dropdown with its own prompts, and its declared `source_columns` get the same
auto-matching and "which column is this?" prompting for free — no changes to the
GUI, pipeline, or export code.
