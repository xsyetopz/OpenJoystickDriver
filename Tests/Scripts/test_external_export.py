import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
EXPORTER = ROOT / "scripts" / "docs" / "issues" / "export.py"


def load_exporter():
    spec = importlib.util.spec_from_file_location("external_issue_export", EXPORTER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load exporter at {EXPORTER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ExternalIssueExportTests(unittest.TestCase):
    def test_sanitizer_removes_ephemeral_queries_and_trailing_whitespace(self):
        exporter = load_exporter()
        source = (
            "first line   \n"
            "https://github.com/example/repo/file?token=secret#anchor\t\n"
            "code remains"
        )

        sanitized = exporter.sanitize_external_text(source)

        self.assertEqual(
            sanitized,
            "first line\nhttps://github.com/example/repo/file#anchor\ncode remains",
        )
        self.assertFalse(any(line.endswith((" ", "\t")) for line in sanitized.splitlines()))


if __name__ == "__main__":
    unittest.main()
