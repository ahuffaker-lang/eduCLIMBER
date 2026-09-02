"""Assessment-specific converters.

Each module here defines the source columns, validation and field mapping for one
assessment type. :data:`CONVERTERS` is what the app shell offers the user; adding
an assessment means writing a sibling module and appending it to this list.
"""

from __future__ import annotations

from typing import Dict, List

from ..core.spec import Converter
from .running_records import RunningRecordsConverter

CONVERTERS: List[Converter] = [
    RunningRecordsConverter(),
]

CONVERTERS_BY_KEY: Dict[str, Converter] = {c.key: c for c in CONVERTERS}


def get_converter(key: str) -> Converter:
    try:
        return CONVERTERS_BY_KEY[key]
    except KeyError:
        raise KeyError(f"No converter registered under '{key}'.") from None
