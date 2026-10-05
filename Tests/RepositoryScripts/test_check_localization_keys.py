from __future__ import annotations

import unittest

from Scripts.Quality import check_localization_keys as guard

KEYS = {"common.ok", "error.one", "error.two"}


class KeyArgumentTests(unittest.TestCase):
    def test_reads_first_argument_of_each_call_form(self) -> None:
        source = (
            'OJDLocalized.string("common.ok")\n'
            'CLILocalized.format("error.one", a, b)\n'
            'LocalizedStringResource("error.two")\n'
            "OJDLocalized.plural(key, count: 2)\n"
        )
        self.assertEqual(
            guard.key_arguments(source),
            [(1, '"common.ok"'), (2, '"error.one"'), (3, '"error.two"'), (4, "key")],
        )

    def test_nested_calls_and_interpolation_do_not_split_the_argument(self) -> None:
        source = 'OJDLocalized.string("error.\\(f(a, b))", x)'
        self.assertEqual(guard.key_arguments(source), [(1, '"error.\\(f(a, b))"')])


class ProblemTests(unittest.TestCase):
    def test_known_literal_passes(self) -> None:
        self.assertIsNone(guard.problems('"common.ok"', KEYS))

    def test_unknown_literal_fails(self) -> None:
        self.assertIn("bogus.key", guard.problems('"bogus.key"', KEYS) or "")

    def test_ternary_checks_both_branches(self) -> None:
        self.assertIsNone(guard.problems('flag ? "error.one" : "error.two"', KEYS))
        self.assertIn(
            "bogus", guard.problems('flag ? "error.one" : "bogus"', KEYS) or ""
        )

    def test_prefix_needs_a_matching_key(self) -> None:
        self.assertIsNone(guard.problems('"error.\\(code)"', KEYS))
        self.assertIsNone(guard.problems('"error." + name', KEYS))
        self.assertIn("nope.", guard.problems('"nope.\\(code)"', KEYS) or "")

    def test_fully_dynamic_key_is_not_judged(self) -> None:
        self.assertIsNone(guard.problems("key", KEYS))


class RepositoryTests(unittest.TestCase):
    def test_en_us_catalog_covers_every_scannable_key(self) -> None:
        missing, _ = guard.check()
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
