from __future__ import annotations

import unittest

from Scripts.Documentation.plain_comment_words import (
    PYTHON_COMMENT,
    rewrite,
)


class SwiftCommentTests(unittest.TestCase):
    def test_payload_in_a_doc_comment_becomes_data(self) -> None:
        # Arrange
        source = "/// The input payload of the report.\nlet payload = 1"

        # Act
        result = rewrite(source)

        # Assert
        self.assertEqual(result, "/// The input data of the report.\nlet payload = 1")

    def test_inline_code_keeps_its_identifier(self) -> None:
        # Arrange
        source = "// Output is suppressed while `suppressed` is true."

        # Act
        result = rewrite(source)

        # Assert
        self.assertEqual(result, "// Output is paused while `suppressed` is true.")

    def test_canonical_equivalence_stays_a_fixed_term(self) -> None:
        # Arrange
        source = "// Compared by canonical equivalence in the canonical frame."

        # Act
        result = rewrite(source)

        # Assert
        self.assertEqual(
            result, "// Compared by canonical equivalence in the standard frame."
        )


class PythonCommentTests(unittest.TestCase):
    def test_hash_comment_is_rewritten(self) -> None:
        # Arrange
        source = "x = 1\n# Each payload is checked.\n"

        # Act
        result = rewrite(source, PYTHON_COMMENT)

        # Assert
        self.assertEqual(result, "x = 1\n# Each block of data is checked.\n")

    def test_pragma_comment_stays(self) -> None:
        # Arrange
        source = "# noqa: E501 payload\n"

        # Act
        result = rewrite(source, PYTHON_COMMENT)

        # Assert
        self.assertEqual(result, source)


if __name__ == "__main__":
    unittest.main()
