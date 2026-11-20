from __future__ import annotations

import io
import unittest
import unittest.mock
from contextlib import redirect_stderr

from Scripts.GUI import terminal


class RenderTests(unittest.TestCase):
    def test_a_longer_line_widens_the_window(self) -> None:
        # Arrange
        short = ["x" * terminal.MIN_COLUMNS]
        long = ["x" * (terminal.MIN_COLUMNS + 40)]

        # Act
        narrow = terminal.render("ojd status", short)
        wide = terminal.render("ojd status", long)

        # Assert
        self.assertGreater(wide.width, narrow.width)

    def test_each_output_line_adds_one_row(self) -> None:
        # Arrange
        one = terminal.render("ojd status", ["a"])

        # Act
        three = terminal.render("ojd status", ["a", "b", "c"])

        # Assert
        from PIL import ImageFont

        font = ImageFont.truetype(terminal.FONT_FILE, terminal.FONT_SIZE)
        line = sum(font.getmetrics()) + terminal.LINE_GAP
        self.assertEqual(three.height - one.height, 2 * line)

    def test_a_line_past_the_terminal_width_wraps_onto_a_new_row(self) -> None:
        # Arrange
        fits = terminal.render("ojd status", ["x" * terminal.MAX_COLUMNS])

        # Act
        wraps = terminal.render("ojd status", ["x" * (terminal.MAX_COLUMNS + 1)])

        # Assert
        self.assertEqual(wraps.width, fits.width)
        self.assertGreater(wraps.height, fits.height)


class RunTests(unittest.TestCase):
    def test_ojd_runs_with_color_off(self) -> None:
        # Arrange
        completed = unittest.mock.Mock(stdout="Service  running\n")

        # Act
        with unittest.mock.patch.object(
            terminal.subprocess, "run", return_value=completed
        ) as run:
            lines = terminal.run_ojd(["status"])

        # Assert
        self.assertEqual(lines, ["Service  running"])
        self.assertEqual(run.call_args.args[0], ["ojd", "status"])
        self.assertEqual(run.call_args.kwargs["env"]["NO_COLOR"], "1")


class MainTests(unittest.TestCase):
    def test_no_ojd_arguments_is_a_usage_error(self) -> None:
        # Arrange
        errors = io.StringIO()

        # Act
        with redirect_stderr(errors):
            code = terminal.main(["ojd-status"])

        # Assert
        self.assertEqual(code, 64)
        self.assertIn("name the ojd arguments", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
