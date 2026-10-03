from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.Command import dispatcher
from Scripts.Documentation.wiki import build as wiki

REPOSITORY = "owner/name"


class TargetInvoked(Exception):
    pass


class WikiBuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.docs = Path(self.temporary.name) / "docs"
        self.docs.mkdir()
        self.output = Path(self.temporary.name) / "wiki"

    def write(self, name: str, text: str) -> None:
        (self.docs / name).write_text(text, encoding="utf-8")

    def build(self) -> list[str]:
        return wiki.build(self.docs, self.output, REPOSITORY, "main")

    def test_rewrites_page_and_repository_links(self) -> None:
        self.write(
            "Home.md",
            "[a](Guide.md) [b](Guide.md#step-one) [c](#local) "
            "[d](../contributing/README.md#top) [e](https://example.com/x.md)\n"
            "\n[ref]: Guide.md#step-two\n",
        )
        self.write("Guide.md", "# Guide\n")
        self.assertEqual(self.build(), ["Guide.md", "Home.md"])
        self.assertEqual(
            (self.output / "Home.md").read_text(encoding="utf-8"),
            "[a](Guide) [b](Guide#step-one) [c](#local) "
            "[d](https://github.com/owner/name/blob/main/contributing/README.md#top) "
            "[e](https://example.com/x.md)\n"
            "\n[ref]: Guide#step-two\n",
        )

    def test_leaves_fenced_code_unchanged(self) -> None:
        text = "```md\n[a](Missing.md)\n```\n"
        self.write("Home.md", text)
        self.build()
        self.assertEqual((self.output / "Home.md").read_text(encoding="utf-8"), text)

    def test_skips_agent_instructions_and_external_archive(self) -> None:
        self.write("Home.md", "# Home\n")
        self.write("AGENTS.md", "# Rules\n")
        (self.docs / "external").mkdir()
        self.assertEqual(self.build(), ["Home.md"])

    def test_rejects_subfolders(self) -> None:
        self.write("Home.md", "# Home\n")
        (self.docs / "guides").mkdir()
        with self.assertRaisesRegex(wiki.WikiBuildError, "guides"):
            self.build()

    def test_rejects_names_that_differ_only_in_case(self) -> None:
        self.write("Home.md", "# Home\n")
        self.write("home.md", "# Home\n")
        if len(list(self.docs.iterdir())) == 1:
            self.skipTest("case-insensitive file system")
        with self.assertRaisesRegex(wiki.WikiBuildError, "case"):
            self.build()

    def test_rejects_missing_pages_and_nested_paths(self) -> None:
        for link in ("Missing.md", "guides/Page.md", "Page"):
            with self.subTest(link=link):
                self.write("Home.md", f"[a]({link})\n")
                with self.assertRaises(wiki.WikiBuildError):
                    self.build()

    def test_rejects_non_empty_output(self) -> None:
        self.write("Home.md", "# Home\n")
        self.output.mkdir()
        (self.output / "stale.md").write_text("", encoding="utf-8")
        with self.assertRaisesRegex(wiki.WikiBuildError, "not empty"):
            self.build()

    def test_repository_docs_build(self) -> None:
        written = wiki.build(wiki.DOCS, self.output, REPOSITORY, "main")
        self.assertIn("Home.md", written)
        self.assertIn("_Sidebar.md", written)
        self.assertNotIn("AGENTS.md", written)

    def test_dispatcher_routes_build_wiki(self) -> None:
        with (
            patch.object(
                dispatcher, "exec_target", side_effect=TargetInvoked
            ) as execute,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["docs", "build-wiki", "out"])
        execute.assert_called_once_with(
            "Documentation/wiki/build.py", ["out"], python=True
        )

    def test_dispatcher_requires_an_output_directory(self) -> None:
        with self.assertRaises(SystemExit):
            dispatcher.dispatch(["docs", "build-wiki"])


if __name__ == "__main__":
    unittest.main()
