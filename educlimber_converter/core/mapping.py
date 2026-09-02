"""Matching a converter's expected columns to the headers in an uploaded file.

Headers that match cleanly are resolved automatically. Anything else -- a
misspelling ("Readng Level"), a renamed export column ("Rdg Lvl A-Z"), a column
that simply isn't there -- is left *unconfirmed*, with ranked suggestions, so the
app can ask the user which column to use instead of failing the run.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from difflib import SequenceMatcher
from typing import Dict, Iterable, List, Optional, Sequence

from .spec import SourceColumn
from .tabular import Table, normalize_header

NOT_IN_FILE = "— not in this file —"

# Below this similarity a header is not even worth suggesting.
SUGGESTION_FLOOR = 0.45


@dataclass
class ColumnMatch:
    """What we think holds one expected column, and how sure we are."""

    column: SourceColumn
    header: Optional[str] = None
    auto: bool = False  # matched by header text, no user confirmation needed
    confirmed: bool = False  # the user picked this one
    suggestions: List[str] = field(default_factory=list)

    @property
    def settled(self) -> bool:
        """True when this column needs no question asked of the user."""
        if self.confirmed:
            return True
        if self.auto and self.header:
            return True
        # An optional column with nothing resembling it in the file needs no question.
        return not self.column.required and not self.suggestions

    @property
    def best_guess(self) -> Optional[str]:
        return self.header or (self.suggestions[0] if self.suggestions else None)

    def describe(self) -> str:
        if self.header:
            return f"'{self.column.label}' -> '{self.header}'"
        return f"'{self.column.label}' -> (not found)"


@dataclass
class ColumnMapping:
    """The full picture of expected columns vs. this file's headers."""

    matches: List[ColumnMatch]
    headers: List[str] = field(default_factory=list)

    def __iter__(self) -> Iterable[ColumnMatch]:
        return iter(self.matches)

    def get(self, key: str) -> Optional[ColumnMatch]:
        for match in self.matches:
            if match.column.key == key:
                return match
        return None

    @property
    def unsettled(self) -> List[ColumnMatch]:
        """Columns the user still has to confirm or point somewhere."""
        return [match for match in self.matches if not match.settled]

    @property
    def needs_confirmation(self) -> bool:
        return bool(self.unsettled)

    def as_dict(self) -> Dict[str, Optional[str]]:
        return {match.column.key: match.header for match in self.matches}

    def apply(self, choices: Dict[str, Optional[str]]) -> None:
        """Record the user's picks. ``None`` means 'this column isn't in the file'."""
        for key, header in choices.items():
            match = self.get(key)
            if match is None:
                continue
            match.header = header or None
            match.confirmed = True

    def problems(self) -> List[str]:
        """Reasons this mapping can't be used yet."""
        issues: List[str] = []
        for match in self.matches:
            if match.column.required and not match.header:
                issues.append(f"No column chosen for '{match.column.label}'.")
        used: Dict[str, List[str]] = {}
        for match in self.matches:
            if match.header:
                used.setdefault(match.header, []).append(match.column.label)
        for header, labels in used.items():
            if len(labels) > 1:
                issues.append(
                    f"'{header}' is assigned to more than one expected column: "
                    + ", ".join(labels)
                    + "."
                )
        return issues


def resolve_columns(table: Table, columns: Sequence[SourceColumn]) -> ColumnMapping:
    """Auto-match what we can; rank suggestions for the rest."""
    matches: List[ColumnMatch] = []
    taken: List[str] = []
    for column in columns:
        header = table.find_column(column.match_names)
        if header in taken:  # a loose match already claimed by an earlier column
            header = None
        if header:
            taken.append(header)
            matches.append(ColumnMatch(column=column, header=header, auto=True))
        else:
            matches.append(
                ColumnMatch(column=column, suggestions=rank_headers(column, table.headers))
            )
    return ColumnMapping(matches=matches, headers=list(table.headers))


def rank_headers(column: SourceColumn, headers: Sequence[str]) -> List[str]:
    """The file's headers, most likely first, for one expected column."""
    scored = []
    for header in headers:
        score = similarity(column, header)
        if score >= SUGGESTION_FLOOR:
            scored.append((score, header))
    scored.sort(key=lambda pair: (-pair[0], pair[1]))
    return [header for _score, header in scored]


def similarity(column: SourceColumn, header: str) -> float:
    """How much *header* looks like any of the names *column* answers to."""
    target = normalize_header(header)
    if not target:
        return 0.0
    best = 0.0
    for name in column.match_names:
        candidate = normalize_header(name)
        if not candidate:
            continue
        ratio = SequenceMatcher(None, candidate, target).ratio()
        if candidate in target or target in candidate:
            ratio = max(ratio, 0.9)
        best = max(best, ratio)
    return best
