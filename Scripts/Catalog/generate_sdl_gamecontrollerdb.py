"""Reduce the pinned SDL_GameControllerDB to the lines the app converts at connect.

Python only filters the text. Swift parses and converts every kept line.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

MAC_PLATFORM = "platform:Mac OS X"
GUID_PATTERN = re.compile(r"[0-9a-f]{32}")


@dataclass
class DatabaseCounts:
    kept: int = 0
    other_platform: int = 0
    unparsable: int = 0
    controller_list: int = 0
    catalog_record: int = 0
    duplicate_guids: int = 0

    def summary(self) -> str:
        return (
            f"SDL_GameControllerDB lines kept {self.kept}, "
            f"other platform {self.other_platform}, unparsable {self.unparsable}, "
            f"skipped controller list {self.controller_list}, "
            f"skipped catalog record {self.catalog_record}, "
            f"duplicate GUIDs {self.duplicate_guids}"
        )


def guid_identity(guid: str) -> tuple[int, int]:
    """The vendor and product a database GUID carries, both little-endian 16-bit fields."""
    vendor = int(guid[10:12] + guid[8:10], 16)
    product = int(guid[18:20] + guid[16:18], 16)
    return vendor, product


def line_key(line: str) -> tuple[str, str]:
    """The GUID and the `crc:` field of a database line; the pair SDL treats as one mapping."""
    fields = line.split(",")
    crc = next((item for item in fields if item.startswith("crc:")), "")
    return fields[0], crc


def license_header(license_text: str) -> str:
    return "".join(
        f"# {line}".rstrip() + "\n" for line in license_text.strip().splitlines()
    )


def reduce_database(
    database: str,
    license_text: str,
    source: str,
    controller_list: set[tuple[int, int]],
    catalog: set[tuple[int, int]],
) -> tuple[str, DatabaseCounts]:
    """The shipped text and what was dropped.

    A line is kept when it names the Mac platform, parses, and its vendor and product are in
    neither the SDL controller list nor the catalog.
    """
    counts = DatabaseCounts()
    kept: list[str] = []
    seen: set[tuple[str, str]] = set()
    for line in database.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(",")
        if MAC_PLATFORM not in fields and any(
            item.startswith("platform:") for item in fields
        ):
            counts.other_platform += 1
            continue
        if (
            len(fields) < 3
            or not GUID_PATTERN.fullmatch(fields[0])
            or not fields[1]
            or MAC_PLATFORM not in fields
        ):
            counts.unparsable += 1
            continue
        identity = guid_identity(fields[0])
        if identity != (0, 0) and identity in controller_list:
            counts.controller_list += 1
        elif identity != (0, 0) and identity in catalog:
            counts.catalog_record += 1
        else:
            key = line_key(line)
            counts.duplicate_guids += key in seen
            seen.add(key)
            kept.append(line)
            counts.kept += 1
    return (
        license_header(license_text)
        + f"\n# Source: {source}\n# Altered from the upstream file: reduced to Mac OS X lines by a generator, do not edit.\n\n"
        + "".join(f"{line}\n" for line in kept),
        counts,
    )
