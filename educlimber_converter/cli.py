"""Command-line front end -- the same pipeline as the GUI, for scripted runs.

    python -m educlimber_converter --cli export.xlsx --assessment-window "Trimester 1" \
        --school-year 2026-2027 [--out result.csv]
"""

from __future__ import annotations

import argparse
import sys
from typing import List, Optional

from .converters import CONVERTERS, CONVERTERS_BY_KEY
from .core.mapping import ColumnMapping
from .core.pipeline import (
    convert_table,
    format_errors,
    load_source,
    match_columns,
    save_result,
    suggested_output_path,
    unmatched_message,
)
from .core.spec import CHOICE, ConverterError
from .core.tabular import SourceFileError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="educlimber-converter",
        description="Convert an assessment export into an eduCLIMBER upload CSV.",
    )
    parser.add_argument("--cli", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("source", help="Path to the source export (.csv or .xlsx)")
    parser.add_argument(
        "--assessment",
        default=CONVERTERS[0].key,
        choices=sorted(CONVERTERS_BY_KEY),
        help="Which converter to run (default: %(default)s)",
    )
    parser.add_argument("--out", help="Where to write the CSV (default: next to the source file)")
    parser.add_argument(
        "--map",
        action="append",
        default=[],
        metavar="EXPECTED=HEADER",
        help=(
            "Point an expected column at a header in your file when the header is "
            "misspelled or renamed, e.g. --map reading_level='Readng Levl'. Repeatable."
        ),
    )
    parser.add_argument(
        "--no-prompt",
        action="store_true",
        help="Never ask about unmatched columns; fail instead (for scripts).",
    )
    for prompt in CONVERTERS[0].prompts:
        flag = "--" + prompt.key.replace("_", "-")
        parser.add_argument(
            flag,
            dest=prompt.key,
            required=True,
            choices=list(prompt.choices) if prompt.kind == CHOICE else None,
            help=prompt.pattern_help or prompt.label,
        )
    return parser


def apply_map_flags(mapping: ColumnMapping, flags: List[str], converter) -> None:
    """Apply ``--map expected=Header`` pairs, validating both sides."""
    known = {column.key: column for column in converter.source_columns}
    for flag in flags:
        key, sep, header = flag.partition("=")
        key, header = key.strip(), header.strip()
        if not sep or not key:
            raise ValueError(f"--map needs the form EXPECTED=HEADER (got {flag!r}).")
        if key not in known:
            raise ValueError(
                f"Unknown expected column {key!r}. Choose from: {', '.join(sorted(known))}."
            )
        if header and header not in mapping.headers:
            raise ValueError(
                f"{header!r} is not a column in this file. "
                f"Columns found: {', '.join(mapping.headers) or '(none)'}"
            )
        mapping.apply({key: header or None})


def prompt_for_columns(mapping: ColumnMapping) -> bool:
    """Ask on the terminal which header holds each unmatched column."""
    print(
        "Some expected columns did not match any header in this file.\n"
        "Pick the column that holds each one (Enter accepts the suggestion, "
        "'s' skips the file).",
        file=sys.stderr,
    )
    for match in list(mapping.unsettled):
        options = list(mapping.headers)
        print(f"\n{match.column.label}" + (f"  (e.g. {match.column.example})" if match.column.example else ""), file=sys.stderr)
        for number, header in enumerate(options, start=1):
            marker = " <- closest match" if match.suggestions and header == match.suggestions[0] else ""
            print(f"  {number}. {header}{marker}", file=sys.stderr)
        if not match.column.required:
            print("  0. not in this file", file=sys.stderr)
        default = match.suggestions[0] if match.suggestions else ""
        while True:
            hint = f" [{default}]" if default else ""
            try:
                answer = input(f"Which column is '{match.column.label}'?{hint} ").strip()
            except EOFError:
                return False
            if answer.lower() in {"s", "q"}:
                return False
            if not answer and default:
                mapping.apply({match.column.key: default})
                break
            if answer == "0" and not match.column.required:
                mapping.apply({match.column.key: None})
                break
            if answer.isdigit() and 1 <= int(answer) <= len(options):
                mapping.apply({match.column.key: options[int(answer) - 1]})
                break
            if answer in options:
                mapping.apply({match.column.key: answer})
                break
            print("  Enter one of the numbers above, or the exact column name.", file=sys.stderr)
    problems = mapping.problems()
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return False
    return True


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    converter = CONVERTERS_BY_KEY[args.assessment]
    answers = {prompt.key: getattr(args, prompt.key, "") for prompt in converter.prompts}

    try:
        table = load_source(args.source)
    except SourceFileError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    mapping = match_columns(converter, table)
    try:
        apply_map_flags(mapping, args.map, converter)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    if mapping.needs_confirmation:
        interactive = sys.stdin.isatty() and not args.no_prompt
        if not interactive or not prompt_for_columns(mapping):
            print(f"Error: {unmatched_message(mapping)}", file=sys.stderr)
            print(
                "\nRun again with --map, e.g. "
                f"--map {mapping.unsettled[0].column.key}='<the header in your file>'.",
                file=sys.stderr,
            )
            return 2

    try:
        result = convert_table(converter, table, answers, mapping)
    except ConverterError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    if result.errors:
        print(
            f"{len(result.errors)} problem(s) found -- nothing was written. "
            "Fix the source file and try again:",
            file=sys.stderr,
        )
        print(format_errors(result.errors), file=sys.stderr)
        return 1

    out = args.out or suggested_output_path(converter, args.source, answers)
    save_result(result, out)
    print(f"Converted {len(result.rows)} students — saved to {out}")
    return 0
