from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import check_text_styles as guard


class FindingTests(unittest.TestCase):
    def test_point_size_fails(self) -> None:
        source = "content.font(.system(size: 15, weight: .medium))\n"
        self.assertEqual(guard.findings(source), [(1, "font set by point size")])

    def test_custom_and_ns_font_sizes_fail(self) -> None:
        source = 'Text("a").font(.custom("Menlo", size: 12))\nlet f = NSFont.systemFont(ofSize: 12)\n'
        self.assertEqual([line for line, _ in guard.findings(source)], [1, 2])

    def test_text_style_with_design_passes(self) -> None:
        self.assertEqual(guard.findings("Text(a).font(.system(.body, design: .monospaced))\n"), [])

    def test_caption_on_secondary_text_passes(self) -> None:
        self.assertEqual(
            guard.findings("Text(a).font(.caption).foregroundColor(.secondary)\n"), []
        )
        self.assertEqual(
            guard.findings(
                "Text(a).font(.caption)\n  .foregroundColor(Color(NSColor.secondaryLabelColor))\n"
            ),
            [],
        )

    def test_planted_caption_fails(self) -> None:
        self.assertEqual(
            guard.findings('Text("Error").font(.caption)\n'),
            [(1, "caption on text that is not secondary")],
        )

    def test_caption_weight_variant_fails(self) -> None:
        self.assertEqual(len(guard.findings("Text(a).font(.caption.weight(.semibold))\n")), 1)

    def test_comment_is_not_code(self) -> None:
        self.assertEqual(guard.findings("// .font(.system(size: 9)) and .caption\n"), [])


class ScanTests(unittest.TestCase):
    def test_names_file_and_line(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            view = root / "Sources/OpenJoystickDriverPresentation/A.swift"
            view.parent.mkdir(parents=True)
            view.write_text("let a = 1\nText(a).font(.caption)\n")
            other = root / "Sources/Other/B.swift"
            other.parent.mkdir(parents=True)
            other.write_text("Text(a).font(.caption)\n")
            self.assertEqual(
                guard.scan(root),
                ["Sources/OpenJoystickDriverPresentation/A.swift:2: caption on text that is not secondary"],
            )

    def test_repository_is_clean(self) -> None:
        self.assertEqual(guard.scan(guard.ROOT), [])


if __name__ == "__main__":
    unittest.main()
