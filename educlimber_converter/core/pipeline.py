"""The assessment-agnostic conversion pipeline: read -> match columns -> map -> write."""

from __future__ import annotations

import os
from typing import Dict, List, Optional, Sequence

from .mapping import ColumnMapping, resolve_columns
from .spec import Converter, ConversionResult, ConverterError
from .tabular import Table, read_table, write_csv


def validate_answers(converter: Converter, answers: Dict[str, str]) -> List[str]:
    """Check the batch-wide prompt answers; returns messages for anything wrong."""
    problems: List[str] = []
    for prompt in converter.prompts:
        message = prompt.validate(answers.get(prompt.key, ""))
        if message:
            problems.append(message)
    return problems


def load_source(path: str) -> Table:
    return read_table(path)


def match_columns(converter: Converter, table: Table) -> ColumnMapping:
    """Auto-match the converter's expected columns against this file's headers.

    Whatever comes back ``needs_confirmation`` is what the caller should put to
    the user (a dialog in the GUI, a prompt or ``--map`` on the command line).
    """
    return resolve_columns(table, converter.source_columns)


def convert_table(
    converter: Converter,
    table: Table,
    answers: Dict[str, str],
    mapping: ColumnMapping,
) -> ConversionResult:
    problems = validate_answers(converter, answers)
    if problems:
        raise ConverterError("\n".join(problems))
    column_problems = mapping.problems()
    if column_problems:
        raise ConverterError("\n".join(column_problems))
    return converter.convert(table, answers, mapping.as_dict())


def convert_file(
    converter: Converter,
    path: str,
    answers: Dict[str, str],
    mapping: Optional[ColumnMapping] = None,
) -> ConversionResult:
    """Read *path* and map it with *converter*.

    Pass *mapping* to reuse column choices the user already confirmed. Without
    one, columns are auto-matched and anything ambiguous raises
    :class:`ConverterError` -- callers that can ask the user should call
    :func:`match_columns` first.
    """
    table = load_source(path)
    if mapping is None:
        mapping = match_columns(converter, table)
        if mapping.needs_confirmation:
            raise ConverterError(unmatched_message(mapping))
    return convert_table(converter, table, answers, mapping)


def unmatched_message(mapping: ColumnMapping) -> str:
    """Plain-language description of what could not be matched."""
    lines = ["These expected columns did not match any header in the file:"]
    for match in mapping.unsettled:
        hint = ""
        if match.suggestions:
            hint = f" -- closest header in the file: '{match.suggestions[0]}'"
        lines.append(f"  {match.column.label}{hint}")
    lines.append("Columns found in this file: " + (", ".join(mapping.headers) or "(none)"))
    return "\n".join(lines)


def save_result(result: ConversionResult, path: str) -> str:
    write_csv(path, result.columns, result.rows)
    return path


def suggested_output_path(converter: Converter, source_path: str, answers: Dict[str, str]) -> str:
    """Default save location: next to the source file, with a descriptive name."""
    folder = os.path.dirname(os.path.abspath(source_path)) if source_path else os.getcwd()
    return os.path.join(folder, safe_filename(converter.default_output_name(answers)))


def safe_filename(name: str) -> str:
    keep = "-_. "
    cleaned = "".join(ch for ch in name if ch.isalnum() or ch in keep).strip()
    return cleaned or "converted.csv"


def format_errors(errors: Sequence, limit: int = 0) -> str:
    lines = [str(error) for error in errors]
    if limit and len(lines) > limit:
        hidden = len(lines) - limit
        lines = lines[:limit] + [f"...and {hidden} more."]
    return "\n".join(lines)
