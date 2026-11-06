from __future__ import annotations

import pathlib
import unittest

from Scripts.Catalog import generate_sdl_gamecontrollerdb as sdl

ROOT = pathlib.Path(__file__).resolve().parents[2]
LICENSE = "Copyright (C) 1997-2025 Sam Lantinga\n\nzlib terms."


def guid(vendor: int, product: int, tail: str = "0000") -> str:
    def le(value: int) -> str:
        return value.to_bytes(2, "little").hex()

    return f"0300{'0000'}{le(vendor)}0000{le(product)}0000{tail}0000"


def line(
    vendor: int, product: int, platform: str = "Mac OS X", tail: str = "0000"
) -> str:
    return f"{guid(vendor, product, tail)},Pad,a:b0,platform:{platform},"


def reduce(*lines: str, controller_list: set | None = None, catalog: set | None = None):
    return sdl.reduce_database(
        "\n".join(lines), LICENSE, "source", controller_list or set(), catalog or set()
    )


class SDLGameControllerDBTests(unittest.TestCase):
    def test_guid_helper_matches_identity(self) -> None:
        self.assertEqual(sdl.guid_identity(guid(0x045E, 0x028E)), (0x045E, 0x028E))

    def test_mac_lines_are_kept_and_other_platforms_dropped(self) -> None:
        text, counts = reduce(line(1, 2), line(3, 4, "Windows"), line(5, 6, "Linux"))
        self.assertEqual((counts.kept, counts.other_platform), (1, 2))
        self.assertIn(guid(1, 2), text)
        self.assertNotIn(guid(3, 4), text)

    def test_controller_list_and_catalog_pads_are_skipped_and_counted(self) -> None:
        _, counts = reduce(
            line(1, 2),
            line(3, 4),
            line(5, 6),
            controller_list={(1, 2)},
            catalog={(3, 4)},
        )
        self.assertEqual(
            (counts.kept, counts.controller_list, counts.catalog_record), (1, 1, 1)
        )

    def test_unparsable_lines_are_counted(self) -> None:
        _, counts = reduce("nothex,Pad,platform:Mac OS X,", "short,platform:Mac OS X")
        self.assertEqual((counts.kept, counts.unparsable), (0, 2))

    def test_duplicate_guid_and_crc_pairs_are_counted_and_kept(self) -> None:
        _, counts = reduce(
            line(1, 2), line(1, 2), line(1, 2).replace("platform", "crc:ab12,platform")
        )
        self.assertEqual((counts.kept, counts.duplicate_guids), (3, 1))

    def test_output_carries_license_source_and_altered_marker(self) -> None:
        text, _ = reduce(line(1, 2))
        self.assertTrue(text.startswith("# Copyright (C) 1997-2025 Sam Lantinga\n"))
        self.assertIn("# Source: source\n# Altered from the upstream file", text)

    def test_third_party_notice_records_the_pinned_commit_and_license(self) -> None:
        notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text()
        self.assertIn("## SDL_GameControllerDB", notices)
        self.assertIn("07af1d50187e94c861c9f9f5d8a55b148f11306b", notices)
        self.assertIn("mdqinc/SDL_GameControllerDB", notices)
        self.assertIn("zlib", notices)
        self.assertIn("Sam Lantinga", notices)


if __name__ == "__main__":
    unittest.main()
