"""Running Records -> eduCLIMBER.

Source export columns: Student ("Last, First"), Student ID, Grade Level,
Reading Level (A-Z), Proficiency Level.
"""

from __future__ import annotations

import csv
import os
import re
import sys
from typing import Dict, List, Optional, Sequence

from ..core.spec import CHOICE, TEXT, ConversionResult, ConverterError, PromptField, RowError
from ..core.tabular import Table

ASSESSMENT_GROUP = "Running Records"
ASSESSMENT_NAME = "Independent Reading Level"

OUTPUT_COLUMNS: Sequence[str] = (
    "Assessment Group",
    "Assessment Name",
    "Assessment Window",
    "School Year",
    "Student ID",
    "Student First Name",
    "Student Middle Initial",
    "Student Last Name",
    "Date of Birth",
    "Student Grade Level",
    "Score Detail 2",
    "Reading Level",
    "Score Detail 1",
    "Proficiency Level",
    "Score",
)

ASSESSMENT_WINDOWS = ("Trimester 1", "Trimester 2", "Trimester 3")
SCHOOL_YEAR_PATTERN = r"^\d{4}-\d{4}$"

# Header text we accept for each source column, most specific first. Matching is
# case-insensitive and ignores punctuation/spacing (see Table.find_column).
SOURCE_COLUMNS = {
    "student": ("Student", "Student Name"),
    "student_id": ("Student ID", "Student Identifier", "Student Number"),
    "grade": ("Grade Level", "Grade"),
    "reading_level": ("Reading Level (A-Z)", "Reading Level", "Independent Reading Level"),
    "proficiency": ("Proficiency Level", "Proficiency"),
}

# Fallback used when Data_Table.csv is missing; the CSV stays the source of truth.
_FALLBACK_LEVELS = [
    ("Below A", 1), ("A", 2), ("B", 3), ("C", 4), ("D", 5), ("E", 6), ("F", 7),
    ("G", 8), ("H", 9), ("I", 10), ("J", 11), ("K", 12), ("L", 13), ("M", 14),
    ("N", 15), ("O", 16), ("P", 17), ("Q", 18), ("R", 19), ("S", 20), ("T", 21),
    ("U", 22), ("V", 23), ("W", 24), ("X", 25), ("Y", 26), ("Z", 27), ("Z+", 28),
    ("MAX", 29),
]


def _data_dir() -> str:
    """Where Data_Table.csv lives, both in source and inside a PyInstaller bundle."""
    bundled = getattr(sys, "_MEIPASS", None)
    if bundled:
        return os.path.join(bundled, "educlimber_converter", "data")
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")


def _level_key(value: str) -> str:
    """Normalize a reading level for lookup: case and inner spacing don't matter."""
    return re.sub(r"\s+", " ", (value or "").strip()).upper()


def load_reading_level_scores() -> Dict[str, int]:
    """Load the Reading Level -> Score table from ``Data_Table.csv``."""
    path = os.path.join(_data_dir(), "Data_Table.csv")
    pairs: List[tuple] = []
    try:
        with open(path, "r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                lookup = {re.sub(r"[^a-z]", "", (k or "").lower()): v for k, v in row.items()}
                display = (lookup.get("displayas") or "").strip()
                numeric = (lookup.get("numericvalue") or "").strip()
                if display and numeric:
                    pairs.append((display, int(float(numeric))))
    except (OSError, ValueError):
        pairs = []
    if not pairs:
        pairs = list(_FALLBACK_LEVELS)
    return {_level_key(display): score for display, score in pairs}


READING_LEVEL_SCORES = load_reading_level_scores()


def split_student_name(raw: str) -> tuple:
    """Split ``"Last, First"`` into ``(first, last)``.

    Extra commas (``"Last, First, Jr"``) keep everything after the first comma as
    the first-name text, which is the safest reading of an unexpected suffix.
    """
    text = (raw or "").strip()
    if "," not in text:
        return "", ""
    last, _, first = text.partition(",")
    return first.strip(), last.strip()


class RunningRecordsConverter:
    key = "running_records"
    display_name = "Running Records"
    description = (
        "Reading assessment export (Student, Student ID, Grade Level, "
        "Reading Level (A-Z), Proficiency Level)."
    )
    output_columns = list(OUTPUT_COLUMNS)
    prompts = (
        PromptField(
            key="assessment_window",
            label="Assessment Window",
            kind=CHOICE,
            choices=ASSESSMENT_WINDOWS,
        ),
        PromptField(
            key="school_year",
            label="School Year",
            kind=TEXT,
            pattern=SCHOOL_YEAR_PATTERN,
            pattern_help="School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
            placeholder="2026-2027",
        ),
    )

    def convert(self, table: Table, answers: Dict[str, str]) -> ConversionResult:
        window = (answers.get("assessment_window") or "").strip()
        school_year = (answers.get("school_year") or "").strip()

        columns = {name: table.find_column(aliases) for name, aliases in SOURCE_COLUMNS.items()}
        missing = [
            SOURCE_COLUMNS[name][0] for name, found in columns.items() if found is None
        ]
        if missing:
            raise ConverterError(
                "The source file is missing these expected column(s): "
                + ", ".join(missing)
                + ".\nColumns found: "
                + (", ".join(table.headers) or "(none)")
            )

        result = ConversionResult(columns=list(OUTPUT_COLUMNS))
        if not table.rows:
            raise ConverterError("The source file has a header row but no student rows.")

        for index, row in enumerate(table.rows):
            row_number = table.row_number(index)
            student = table.value(row, columns["student"])
            student_id = table.value(row, columns["student_id"])
            grade = table.value(row, columns["grade"])
            reading_level = table.value(row, columns["reading_level"])
            proficiency = table.value(row, columns["proficiency"])

            row_errors: List[str] = []

            first_name, last_name = split_student_name(student)
            if not student:
                row_errors.append("Student name is blank.")
            elif "," not in student:
                row_errors.append(
                    f"Student name {student!r} is not in 'Last, First' format."
                )
            elif not first_name or not last_name:
                row_errors.append(
                    f"Student name {student!r} is missing a first or last name."
                )

            if not student_id:
                row_errors.append("Student ID is blank.")

            score = self.score_for(reading_level)
            if score is None:
                if not reading_level:
                    row_errors.append("Reading Level (A-Z) is blank.")
                else:
                    row_errors.append(
                        f"Reading Level {reading_level!r} is not in the reading level table."
                    )

            if row_errors:
                label = student or f"Student ID {student_id}" if student_id else student
                prefix = f"{label} -- " if label else ""
                for message in row_errors:
                    result.errors.append(RowError(row_number, prefix + message))
                continue

            result.rows.append(
                {
                    "Assessment Group": ASSESSMENT_GROUP,
                    "Assessment Name": ASSESSMENT_NAME,
                    "Assessment Window": window,
                    "School Year": school_year,
                    "Student ID": student_id,
                    "Student First Name": first_name,
                    "Student Middle Initial": "",
                    "Student Last Name": last_name,
                    "Date of Birth": "",
                    "Student Grade Level": grade,
                    # Score Detail 2 / Reading Level and Score Detail 1 /
                    # Proficiency Level are deliberate duplicates: eduCLIMBER's
                    # import format wants the same value in both columns.
                    "Score Detail 2": reading_level,
                    "Reading Level": reading_level,
                    "Score Detail 1": proficiency,
                    "Proficiency Level": proficiency,
                    "Score": score,
                }
            )
        return result

    @staticmethod
    def score_for(reading_level: str) -> Optional[int]:
        return READING_LEVEL_SCORES.get(_level_key(reading_level))

    def default_output_name(self, answers: Dict[str, str]) -> str:
        window = (answers.get("assessment_window") or "").strip().replace(" ", "")
        school_year = (answers.get("school_year") or "").strip()
        parts = [part for part in ("Running_Records", window, school_year, "educlimber") if part]
        return "_".join(parts) + ".csv"
