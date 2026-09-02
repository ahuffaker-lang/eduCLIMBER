# eduCLIMBER Assessment Converter (macOS)

A native Mac app that reshapes a **Running Records** reading-assessment export
into the 15-column CSV that eduCLIMBER's upload expects.

Pick the export → choose the assessment window and school year → the app validates
every row and writes the eduCLIMBER file. Swift + AppKit, built with Xcode, with no
third-party dependencies (`.xlsx` files are read directly).

## Getting the app

**Option 1 — download a build (no Xcode needed).** Every push to a build branch
runs the *macOS app* workflow on GitHub. Open the repository's **Actions** tab,
click the most recent green run, and download the `eduCLIMBER-Converter-macos`
artifact. Unzip it and drag `eduCLIMBER Converter.app` into `/Applications`.

**Option 2 — build it yourself:**

```bash
./scripts/build_app.sh          # tests, builds, signs, produces build/eduCLIMBER Converter.app
```

**Option 3 — Xcode.** `File > Open…`, select `Package.swift`, choose the
**eduCLIMBER-Converter** scheme, and press Run (⌘R). `⌘U` runs the tests.

### First launch

The app is signed ad-hoc, not with a paid Apple Developer certificate, so macOS
treats it as coming from an unidentified developer. The first time only:
**right-click the app → Open → Open**. After that, double-clicking works normally.
(Opening it by double-click first shows a dialog with no Open button — that is
Gatekeeper, not a broken build.)

Requires macOS 12 or later. The downloaded build is universal (Apple Silicon and
Intel).

## Source file

CSV or Excel (`.xlsx`), with these columns. Header text is matched
case-insensitively and ignoring punctuation and spacing, so `reading_level` or
`READING LEVEL (A-Z)` are fine:

| Column | Notes |
|---|---|
| The student name | either one `Student` column in `"Last, First"` form, **or** separate `First Name` and `Last Name` columns — whichever your export has |
| `Student ID` | required |
| `Grade Level` | `K`, `1` … `8` |
| `Reading Level (A-Z)` | `Below A`, `A`–`Z` |
| `Proficiency Level` | passed through as-is |

### Either name format

Assessment exports split the student name differently, so the app takes either
shape and works out which one it is:

- a single `Student` column holding `Gomez, Maria`, or
- separate `First Name` and `Last Name` columns holding `Maria` and `Gomez`.

Nothing to configure — it detects the columns and fills eduCLIMBER's
`Student First Name` / `Student Last Name` either way. If a file happens to have
both, the already-split columns win (no parsing, nothing to guess), and the
combined column fills in for any row where they're empty. A file with neither
gets a plain message saying it needs one shape or the other, rather than an error
on every row.

Note that a combined column still has to use the comma (`Last, First`). A name
written `Maria Gomez` is flagged rather than guessed at, because splitting on the
space silently mangles multi-word surnames like `Van Dyke`.

`samples/sample_running_records.csv` (combined) and
`samples/sample_running_records_split_names.csv` (split) are small examples to
try it on.

### When a column is misnamed or misspelled

The app never guesses at a header it doesn't recognize. If a column is misspelled
(`Readng Levl (A-Z)`) or renamed (`Rdg Level A-Z`), a **Match Columns** sheet asks
which column in your file holds each expected one, with the closest header
pre-selected — accept it or pick another from the menu. Choose
`— not in this file —` for a column that genuinely isn't there (only allowed for
optional columns). One file column can't be assigned to two expected columns.

Your choices are remembered for that file, so re-converting after changing the
window or school year doesn't ask again. **Match Columns…** in the main window
opens the same sheet any time, including when everything matched automatically —
useful for checking a column wasn't matched to the wrong header.

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
- `Score` comes from the reading-level table (`Below A` → 1, `A` → 2, … `Z` → 27,
  `Z+` → 28, `MAX` → 29). The table lives in `Sources/EduClimberKit/ReadingLevels.swift`;
  `Resources/Data_Table.csv` is the same data as a reference file, and a unit test
  fails if the two ever drift apart.

Default file name: `Running_Records_<Window>_<SchoolYear>_educlimber.csv`, saved
wherever you choose (the source folder is suggested). Written as plain UTF-8 with
no byte-order mark, so eduCLIMBER reads the first header cleanly.

## Validation

The conversion is all-or-nothing: if any row has a problem, **no file is written**
and the app lists every offending row by its spreadsheet row number, so you can fix
the source and re-run. Rows are flagged for an unrecognized or blank reading level,
a blank Student ID, a blank first or last name, and a combined student name that
isn't in `Last, First` form. An invalid
school year stops the run before any row is read, and an unmatched column is asked
about rather than failing. Completely blank rows are skipped rather than flagged —
and on an Excel file, row numbers still count them, so they match what you see in
Excel.

School year must match `YYYY-YYYY` exactly — no spaces.

## Project layout

```
Package.swift               open this in Xcode
Sources/
  EduClimberKit/            all the logic, no UI — this is what the tests cover
    Table.swift             loaded spreadsheet + loose header matching
    CSVReader.swift         RFC 4180 parsing, delimiter and encoding detection
    XLSXReader.swift        .xlsx via ZipArchive + SimpleXML
    ZipArchive.swift        minimal ZIP reader (Apple's Compression framework)
    SimpleXML.swift         XMLParser helpers for the workbook parts
    ColumnMapping.swift     match expected columns to real headers, rank suggestions
    Converter.swift         PromptField / SourceColumn / AssessmentConverter
    RunningRecordsConverter.swift   source columns, field mapping, prompts
    ReadingLevels.swift     the Reading Level → Score table
    CSVWriter.swift         the eduCLIMBER CSV
    Pipeline.swift          read → match columns → map → save
  EduClimberConverterApp/   AppKit UI
    MainWindowController.swift   the main window, built from the converter
    ColumnMatchSheet.swift       "which column is this?" sheet
Tests/EduClimberKitTests/   XCTest suite (`swift test` or ⌘U)
scripts/build_app.sh        builds and signs eduCLIMBER Converter.app
```

## Adding another assessment type

The shell (file picking, prompts, column matching, validation display, CSV export)
is assessment-agnostic. To add one: write a type conforming to `AssessmentConverter`
with its own `prompts`, `sourceColumns`, `outputColumns` and `convert(...)`, then add
it to the `converters` array in `MainWindowController`. It appears in the assessment
menu with its own prompts, and its declared `sourceColumns` get the same
auto-matching and "which column is this?" prompting for free.

## History

Earlier commits on this branch contain a Python/Tkinter implementation of the same
converter, replaced by this native app. It is still in the git history if it is ever
needed.
