"""Matching expected columns to real headers, including misspelled ones."""

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from educlimber_converter.cli import apply_map_flags, main as cli_main
from educlimber_converter.converters.running_records import RunningRecordsConverter
from educlimber_converter.core.mapping import resolve_columns
from educlimber_converter.core.pipeline import (
    convert_file,
    convert_table,
    load_source,
    match_columns,
)
from educlimber_converter.core.spec import ConverterError

ANSWERS = {"assessment_window": "Trimester 1", "school_year": "2026-2027"}
GOOD_HEADER = "Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"
TYPO_HEADER = "Studnt,Student ID,Grade Level,Readng Levl (A-Z),Proficiency Level\n"
ROW = '"Gomez, Maria",100234,K,Below A,At Standard\n'


@pytest.fixture()
def converter():
    return RunningRecordsConverter()


def write(tmp_path, header, body=ROW, name="source.csv"):
    path = tmp_path / name
    path.write_text(header + body, encoding="utf-8")
    return str(path)


def test_clean_headers_need_no_questions(tmp_path, converter):
    mapping = match_columns(converter, load_source(write(tmp_path, GOOD_HEADER)))
    assert not mapping.needs_confirmation
    assert mapping.as_dict()["reading_level"] == "Reading Level (A-Z)"


def test_misspelled_headers_are_asked_about_not_guessed(tmp_path, converter):
    mapping = match_columns(converter, load_source(write(tmp_path, TYPO_HEADER)))
    unsettled = {match.column.key for match in mapping.unsettled}
    assert unsettled == {"student", "reading_level"}
    # ...but the closest header is offered first, ready to be accepted.
    assert mapping.get("student").suggestions[0] == "Studnt"
    assert mapping.get("reading_level").suggestions[0] == "Readng Levl (A-Z)"


def test_renamed_column_is_suggested(tmp_path, converter):
    header = "Student,Student ID,Grade Level,Rdg Level A-Z,Proficiency Level\n"
    mapping = match_columns(converter, load_source(write(tmp_path, header)))
    assert "Rdg Level A-Z" in mapping.get("reading_level").suggestions


def test_confirmed_choice_makes_the_conversion_run(tmp_path, converter):
    table = load_source(write(tmp_path, TYPO_HEADER))
    mapping = match_columns(converter, table)
    mapping.apply({"student": "Studnt", "reading_level": "Readng Levl (A-Z)"})
    assert not mapping.needs_confirmation
    result = convert_table(converter, table, ANSWERS, mapping)
    assert result.ok
    assert result.rows[0]["Student Last Name"] == "Gomez"
    assert result.rows[0]["Score"] == 1


def test_same_header_cannot_feed_two_expected_columns(tmp_path, converter):
    table = load_source(write(tmp_path, TYPO_HEADER))
    mapping = match_columns(converter, table)
    mapping.apply({"student": "Studnt", "reading_level": "Studnt"})
    problems = mapping.problems()
    assert any("more than one expected column" in problem for problem in problems)
    with pytest.raises(ConverterError):
        convert_table(converter, table, ANSWERS, mapping)


def test_required_column_left_unset_is_reported(tmp_path, converter):
    table = load_source(write(tmp_path, TYPO_HEADER))
    mapping = match_columns(converter, table)
    mapping.apply({"student": None, "reading_level": "Readng Levl (A-Z)"})
    assert mapping.problems() == ["No column chosen for 'Student'."]


def test_convert_file_without_a_mapping_explains_the_mismatch(tmp_path, converter):
    with pytest.raises(ConverterError) as exc:
        convert_file(converter, write(tmp_path, TYPO_HEADER), ANSWERS)
    message = str(exc.value)
    assert "Reading Level (A-Z)" in message and "Readng Levl (A-Z)" in message


def test_map_flags(tmp_path, converter):
    mapping = match_columns(converter, load_source(write(tmp_path, TYPO_HEADER)))
    apply_map_flags(mapping, ["student=Studnt", "reading_level=Readng Levl (A-Z)"], converter)
    assert not mapping.needs_confirmation

    with pytest.raises(ValueError, match="Unknown expected column"):
        apply_map_flags(mapping, ["nope=Studnt"], converter)
    with pytest.raises(ValueError, match="not a column in this file"):
        apply_map_flags(mapping, ["student=Missing Header"], converter)
    with pytest.raises(ValueError, match="EXPECTED=HEADER"):
        apply_map_flags(mapping, ["student"], converter)


def test_cli_maps_columns_end_to_end(tmp_path, capsys):
    source = write(tmp_path, TYPO_HEADER)
    out = str(tmp_path / "out.csv")
    code = cli_main(
        [
            source,
            "--assessment-window", "Trimester 1",
            "--school-year", "2026-2027",
            "--map", "student=Studnt",
            "--map", "reading_level=Readng Levl (A-Z)",
            "--out", out,
        ]
    )
    assert code == 0
    assert "Converted 1 students" in capsys.readouterr().out
    assert os.path.exists(out)


def test_cli_without_map_fails_with_guidance(tmp_path, capsys):
    code = cli_main(
        [
            write(tmp_path, TYPO_HEADER),
            "--assessment-window", "Trimester 1",
            "--school-year", "2026-2027",
            "--no-prompt",
        ]
    )
    assert code == 2
    err = capsys.readouterr().err
    assert "did not match any header" in err and "--map student=" in err
