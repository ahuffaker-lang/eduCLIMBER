"""Shared vocabulary for assessment converters.

Everything in this module is assessment-agnostic. A converter module (see
``educlimber_converter.converters``) describes *what* it needs from the user and
*how* to map a source table; the app shell (file picking, prompting, CSV export)
is written against these types only, so adding a second assessment type means
adding a module -- not touching the shell.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Protocol, Sequence

from .tabular import Table

TEXT = "text"
CHOICE = "choice"


@dataclass(frozen=True)
class PromptField:
    """One value the user must supply for a whole batch."""

    key: str
    label: str
    kind: str = TEXT
    choices: Sequence[str] = ()
    pattern: Optional[str] = None
    pattern_help: str = ""
    placeholder: str = ""

    def validate(self, value: str) -> Optional[str]:
        """Return an error message, or ``None`` when *value* is acceptable."""
        value = (value or "").strip()
        if not value:
            return f"{self.label} is required."
        if self.kind == CHOICE and value not in self.choices:
            return f"{self.label} must be one of: {', '.join(self.choices)}."
        if self.pattern and not re.match(self.pattern, value):
            return self.pattern_help or f"{self.label} is not in the expected format."
        return None


@dataclass(frozen=True)
class SourceColumn:
    """A column a converter needs to find in the uploaded file.

    Declaring these (rather than hunting for headers inside ``convert``) is what
    lets the shell auto-match headers, and ask the user to point at the right
    column when a header is misspelled or named something unexpected.
    """

    key: str
    label: str  # the canonical name, shown to the user when asking
    aliases: Sequence[str] = ()
    required: bool = True
    example: str = ""

    @property
    def match_names(self) -> Sequence[str]:
        return (self.label,) + tuple(self.aliases)


@dataclass(frozen=True)
class RowError:
    """A single problem found in the source file."""

    row_number: int  # 1-based spreadsheet row number, header included
    message: str

    def __str__(self) -> str:
        return f"Row {self.row_number}: {self.message}"


@dataclass
class ConversionResult:
    columns: List[str] = field(default_factory=list)
    rows: List[Dict[str, Any]] = field(default_factory=list)
    errors: List[RowError] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


class ConverterError(Exception):
    """Raised for problems with the file as a whole (e.g. a missing column)."""


class Converter(Protocol):
    """The contract every assessment converter implements."""

    key: str
    display_name: str
    description: str
    prompts: Sequence[PromptField]
    source_columns: Sequence[SourceColumn]
    output_columns: Sequence[str]

    def convert(
        self, table: Table, answers: Dict[str, str], columns: Dict[str, Optional[str]]
    ) -> ConversionResult:
        """Map *table* into output rows.

        *columns* maps each :class:`SourceColumn` key to the header in this file
        that holds it -- auto-matched, or confirmed by the user.
        """
        ...

    def default_output_name(self, answers: Dict[str, str]) -> str: ...
