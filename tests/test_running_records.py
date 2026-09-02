import csv
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from educlimber_converter.converters.running_records import (
    OUTPUT_COLUMNS,
    RunningRecordsConverter,
    load_reading_level_scores,
    split_student_name,
)
from educlimber_converter.core.pipeline import convert_file, save_result, validate_answers
from educlimber_converter.core.spec import ConverterError
from educlimber_converter.core.tabular import SourceFileError, read_table

ANSWERS = {"assessment_window": "Trimester 2", "school_year": "2026-2027"}
HEADER = "Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"


def write_csv_file(tmp_path, body, header=HEADER, name="source.csv"):
    path = tmp_path / name
    path.write_text(header + body, encoding="utf-8")
    return str(path)


@pytest.fixture()
def converter():
    return RunningRecordsConverter()


def test_lookup_table_matches_spec():
    scores = load_reading_level_scores()
    assert len(scores) == 29
    assert scores["BELOW A"] == 1
    assert scores["A"] == 2
    assert scores["Z"] == 27
    assert scores["Z+"] == 28
    assert scores["MAX"] == 29


def test_output_column_order():
    assert list(OUTPUT_COLUMNS) == [
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
    ]


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Gomez, Maria", ("Maria", "Gomez")),
        ("  Smith ,  John  ", ("John", "Smith")),
        ("Van Dyke, Anna Lee", ("Anna Lee", "Van Dyke")),
        ("NoComma", ("", "")),
    ],
)
def test_split_student_name(raw, expected):
    assert split_student_name(raw) == expected


def test_full_row_mapping(tmp_path, converter):
    path = write_csv_file(tmp_path, '"Gomez, Maria",123456,3,Below A,Far Below Standard\n')
    result = convert_file(converter, path, ANSWERS)
    assert result.ok
    row = result.rows[0]
    assert row == {
        "Assessment Group": "Running Records",
        "Assessment Name": "Independent Reading Level",
        "Assessment Window": "Trimester 2",
        "School Year": "2026-2027",
        "Student ID": "123456",
        "Student First Name": "Maria",
        "Student Middle Initial": "",
        "Student Last Name": "Gomez",
        "Date of Birth": "",
        "Student Grade Level": "3",
        "Score Detail 2": "Below A",
        "Reading Level": "Below A",
        "Score Detail 1": "Far Below Standard",
        "Proficiency Level": "Far Below Standard",
        "Score": 1,
    }


def test_duplicate_columns_stay_in_sync(tmp_path, converter):
    path = write_csv_file(tmp_path, '"Lee, Sam",1,K,M,At Standard\n')
    row = convert_file(converter, path, ANSWERS).rows[0]
    assert row["Score Detail 2"] == row["Reading Level"] == "M"
    assert row["Score Detail 1"] == row["Proficiency Level"] == "At Standard"
    assert row["Score"] == 14


def test_headers_match_loosely_and_case_insensitively(tmp_path, converter):
    header = "  STUDENT ,student_id,grade level,Reading Level A-Z,proficiency level\n"
    path = write_csv_file(tmp_path, '"Gomez, Maria",7,2,C,At Standard\n', header=header)
    result = convert_file(converter, path, ANSWERS)
    assert result.ok
    assert result.rows[0]["Student First Name"] == "Maria"
    assert result.rows[0]["Score"] == 4


def test_grade_k_passes_through(tmp_path, converter):
    path = write_csv_file(tmp_path, '"Ng, Ada",9,K,A,At Standard\n')
    assert convert_file(converter, path, ANSWERS).rows[0]["Student Grade Level"] == "K"


def test_unknown_reading_level_is_flagged(tmp_path, converter):
    body = '"Ng, Ada",9,K,A,At Standard\n"Ray, Jo",10,1,QQ,At Standard\n'
    result = convert_file(converter, write_csv_file(tmp_path, body), ANSWERS)
    assert len(result.errors) == 1
    assert result.errors[0].row_number == 3
    assert "not in the reading level table" in result.errors[0].message
    assert not result.ok


def test_blank_reading_level_and_missing_id_are_flagged(tmp_path, converter):
    body = '"Ng, Ada",,K,A,At Standard\n"Ray, Jo",10,1,,At Standard\n'
    result = convert_file(converter, write_csv_file(tmp_path, body), ANSWERS)
    messages = [error.message for error in result.errors]
    assert any("Student ID is blank" in m for m in messages)
    assert any("Reading Level (A-Z) is blank" in m for m in messages)


def test_unparseable_student_name_is_flagged(tmp_path, converter):
    result = convert_file(converter, write_csv_file(tmp_path, "Maria Gomez,9,1,C,At\n"), ANSWERS)
    assert "not in 'Last, First' format" in result.errors[0].message


def test_missing_column_raises(tmp_path, converter):
    header = "Student,Student ID,Grade Level,Proficiency Level\n"
    path = write_csv_file(tmp_path, '"Ng, Ada",9,K,At Standard\n', header=header)
    with pytest.raises(ConverterError) as exc:
        convert_file(converter, path, ANSWERS)
    assert "Reading Level (A-Z)" in str(exc.value)


def test_empty_file_raises(tmp_path, converter):
    with pytest.raises(ConverterError):
        convert_file(converter, write_csv_file(tmp_path, ""), ANSWERS)
    with pytest.raises(SourceFileError):
        read_table(write_csv_file(tmp_path, "", header="", name="blank.csv"))


@pytest.mark.parametrize("year", ["2026-2027", "2025-2026"])
def test_valid_school_years(converter, year):
    assert validate_answers(converter, {**ANSWERS, "school_year": year}) == []


@pytest.mark.parametrize("year", ["2026 - 2027", "26-27", "2026/2027", "", "2026-20277"])
def test_invalid_school_years(converter, year):
    problems = validate_answers(converter, {**ANSWERS, "school_year": year})
    assert problems and "School Year" in problems[0]


def test_invalid_assessment_window(converter):
    problems = validate_answers(converter, {**ANSWERS, "assessment_window": "Trimester 4"})
    assert problems and "Assessment Window" in problems[0]


def test_blank_rows_are_skipped(tmp_path, converter):
    body = '"Ng, Ada",9,K,A,At Standard\n,,,,\n"Ray, Jo",10,1,B,At Standard\n'
    result = convert_file(converter, write_csv_file(tmp_path, body), ANSWERS)
    assert result.ok and len(result.rows) == 2


def test_saved_csv_has_exact_columns(tmp_path, converter):
    path = write_csv_file(tmp_path, '"Ng, Ada",9,K,A,At Standard\n')
    result = convert_file(converter, path, ANSWERS)
    out = str(tmp_path / "out.csv")
    save_result(result, out)
    with open(out, encoding="utf-8", newline="") as handle:
        assert not handle.read(1) == "\ufeff"  # no BOM in the eduCLIMBER upload
        handle.seek(0)
        reader = csv.reader(handle)
        assert next(reader) == list(OUTPUT_COLUMNS)
        assert next(reader)[-1] == "2"


def test_default_output_name(converter):
    assert converter.default_output_name(ANSWERS) == (
        "Running_Records_Trimester2_2026-2027_educlimber.csv"
    )
