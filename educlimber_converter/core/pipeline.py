"""The assessment-agnostic conversion pipeline: read -> validate -> map -> write."""

from __future__ import annotations

import os
from typing import Dict, List, Sequence

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


def convert_file(converter: Converter, path: str, answers: Dict[str, str]) -> ConversionResult:
    """Read *path* and map it with *converter*.

    Raises :class:`ConverterError` for whole-file problems (bad prompt answers,
    missing columns); per-row problems come back in ``result.errors``.
    """
    problems = validate_answers(converter, answers)
    if problems:
        raise ConverterError("\n".join(problems))
    return converter.convert(load_source(path), answers)


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
