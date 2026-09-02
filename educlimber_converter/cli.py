"""Command-line front end -- the same pipeline as the GUI, for scripted runs.

    python -m educlimber_converter --cli export.xlsx --assessment-window "Trimester 1" \
        --school-year 2026-2027 [--out result.csv]
"""

from __future__ import annotations

import argparse
import sys
from typing import List, Optional

from .converters import CONVERTERS, CONVERTERS_BY_KEY
from .core.pipeline import (
    convert_file,
    format_errors,
    save_result,
    suggested_output_path,
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


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    converter = CONVERTERS_BY_KEY[args.assessment]
    answers = {prompt.key: getattr(args, prompt.key, "") for prompt in converter.prompts}

    try:
        result = convert_file(converter, args.source, answers)
    except (ConverterError, SourceFileError) as exc:
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
