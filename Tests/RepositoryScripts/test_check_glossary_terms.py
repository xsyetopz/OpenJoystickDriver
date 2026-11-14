from __future__ import annotations

import plistlib
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar

from Scripts.Quality import check_glossary_terms as guard
from Scripts.Quality.check_localization_keys import StringsEntry

GLOSSARY = """# Glossary

## Terms

| Term | Definition | Replaces | Command line |
| --- | --- | --- | --- |
| profile | A set. | "remapping profile" | `ojd profile` |
| connection | How. | "transport", "Wireless Link", "protocol" where it names this | `connection` |

## Rules
"""


class GlossaryTests(unittest.TestCase):
    def test_reads_each_quoted_phrase_of_the_replaces_column(self) -> None:
        self.assertEqual(
            guard.glossary_terms(GLOSSARY),
            {
                "profile": ["remapping profile"],
                "connection": ["transport", "Wireless Link"],
            },
        )

    def test_the_repository_glossary_lists_its_terms(self) -> None:
        terms = guard.glossary_terms((guard.ROOT / guard.GLOSSARY).read_text("utf-8"))
        self.assertIn("virtual gamepad", terms)
        self.assertIn("persona", terms["virtual gamepad"])
        self.assertIn("dext", terms["Xbox USB driver"])


class ReplacedWordTests(unittest.TestCase):
    words: ClassVar[dict[str, list[str]]] = {
        "profile": ["remapping profile"],
        "connection": ["transport"],
    }

    def test_a_replaced_word_fails_without_regard_to_case(self) -> None:
        entry = StringsEntry("ui.a.b", "Choose a Remapping Profile.", "L.")
        self.assertEqual(
            guard.replaced_word_problems([entry], self.words, {}),
            ["'ui.a.b': 'remapping profile' replaced by 'profile'"],
        )

    def test_a_word_inside_a_longer_word_passes(self) -> None:
        entry = StringsEntry(
            "ui.a.b", "Set writeTransports or transport-extension.", "L."
        )
        self.assertEqual(guard.replaced_word_problems([entry], self.words, {}), [])

    def test_a_kept_key_passes_and_a_stale_kept_key_fails(self) -> None:
        entries = [
            StringsEntry("error.E1.message", "Set transport to USB.", "L."),
            StringsEntry("ui.a.b", "Fine.", "L."),
        ]
        kept = {"error.E1.message": "a file key", "ui.a.b": "x", "ui.gone": "y"}
        self.assertEqual(
            guard.replaced_word_problems(entries, self.words, kept),
            [
                "kept key 'ui.a.b' holds no replaced word",
                "kept key 'ui.gone' is not in the en-US strings",
            ],
        )

    def test_every_kept_key_has_a_reason(self) -> None:
        self.assertTrue(all(guard.KEPT.values()))


class TranslationTests(unittest.TestCase):
    english: ClassVar[list[StringsEntry]] = [
        StringsEntry("ui.a", "Profile", "L."),
        StringsEntry("ui.b", "Profile:", "L."),
        StringsEntry("ui.c", "Open the profile", "L."),
    ]

    def test_values_that_hold_only_the_term_share_one_translation(self) -> None:
        anchors = guard.term_anchors(self.english, ["profile"])
        self.assertEqual(anchors, {"profile": ["ui.a", "ui.b"]})
        same = [
            StringsEntry("ui.a", "Profil", "L."),
            StringsEntry("ui.b", "profil:", "L."),
        ]
        self.assertEqual(guard.translation_problems(same, anchors), [])
        other = [
            StringsEntry("ui.a", "Profil", "L."),
            StringsEntry("ui.b", "Satz", "L."),
        ]
        self.assertEqual(
            guard.translation_problems(other, anchors),
            ["'profile' has 2 translations: 'Profil' (ui.a), 'Satz' (ui.b)"],
        )


class WikiTests(unittest.TestCase):
    terms: ClassVar[dict[str, list[str]]] = {
        "virtual gamepad": ["persona"],
        "virtual gamepad kind": [],
    }

    def test_the_first_use_of_a_term_must_link_to_the_glossary(self) -> None:
        pages = {
            "A.md": guard.wiki_prose(
                "A virtual gamepad reads. [virtual gamepad](Glossary.md#terms)"
            ),
            "B.md": guard.wiki_prose(
                "A [virtual gamepad](Glossary.md#terms) reads. A virtual gamepad."
            ),
            "C.md": guard.wiki_prose(
                "The [virtual gamepad kind](Glossary.md#terms) is `a virtual gamepad`."
            ),
        }
        self.assertEqual(
            guard.wiki_first_use_problems(pages, list(self.terms)),
            ["A.md: first use of 'virtual gamepad' does not link to Glossary.md#terms"],
        )

    def test_a_replaced_word_in_prose_fails_but_not_in_code(self) -> None:
        pages = {
            "A.md": guard.wiki_prose(
                "The persona. The `persona` key.\n```\npersona\n```"
            )
        }
        self.assertEqual(
            guard.wiki_replaced_word_problems(pages, self.terms, {}),
            ["A.md: 'persona' replaced by 'virtual gamepad'"],
        )
        self.assertEqual(
            guard.wiki_replaced_word_problems(
                pages, self.terms, {("A.md", "persona"): "x"}
            ),
            [],
        )

    def test_a_kept_wiki_word_that_the_page_lost_fails(self) -> None:
        self.assertEqual(
            guard.wiki_replaced_word_problems(
                {"A.md": "Fine."}, self.terms, {("A.md", "persona"): "x"}
            ),
            ["kept wiki word ('A.md', 'persona') is not in the page"],
        )

    def test_the_repository_wiki_names_each_term_once_and_links_it(self) -> None:
        pages = guard.wiki_pages(guard.ROOT)
        terms = guard.glossary_terms((guard.ROOT / guard.GLOSSARY).read_text("utf-8"))
        self.assertEqual(guard.wiki_first_use_problems(pages, list(terms)), [])
        self.assertEqual(
            guard.wiki_replaced_word_problems(pages, terms, guard.WIKI_KEPT), []
        )


class TermStringTests(unittest.TestCase):
    def test_the_repository_strings_name_the_terms_as_the_glossary_does(self) -> None:
        self.assertEqual(guard.term_string_problems(guard.ROOT), [])

    def test_the_kind_control_holds_no_profile_persona_or_identifier(self) -> None:
        keys = guard.strings_entries(
            (guard.ROOT / guard.CATALOG_DIRECTORY / "Localizable.strings").read_text(
                "utf-8"
            )
        )
        kind = {e.key: e.value for e in keys if guard.KIND_KEYS.match(e.key)}
        self.assertEqual(len(kind), 4)
        self.assertEqual(kind["ui.virtualProfile.title"], "Virtual gamepad kind")
        self.assertFalse(set(kind.values()) & set(guard.KIND_IDENTIFIERS))
        for value in kind.values():
            self.assertNotRegex(value.lower(), r"\b(profile|persona)\b")


class ScanTests(unittest.TestCase):
    def test_names_the_bundle_of_a_second_translation(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            (root / guard.GLOSSARY).parent.mkdir(parents=True)
            (root / guard.GLOSSARY).write_text(GLOSSARY)
            for name, (first, second) in {
                "en-US": ("Profile", "Profile"),
                "de-DE": ("Profil", "Satz"),
            }.items():
                directory = root / guard.RESOURCES_DIRECTORY / f"{name}.lproj"
                directory.mkdir(parents=True)
                (directory / "Localizable.strings").write_text(
                    f'/* L. */\n"ui.a" = "{first}";\n/* L. */\n"ui.b" = "{second}";\n'
                )
                (directory / "Localizable.stringsdict").write_bytes(plistlib.dumps({}))
            self.assertEqual(
                guard.scan(root, kept={}),
                [
                    "de-DE.lproj: 'profile' has 2 translations: 'Profil' (ui.a), 'Satz' (ui.b)"
                ],
            )

    def test_repository_is_clean(self) -> None:
        self.assertEqual(guard.scan(guard.ROOT), [])


if __name__ == "__main__":
    unittest.main()
