from __future__ import annotations

import importlib.util
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from Scripts.GUI import annotate
from Scripts.GUI.annotate import Box, Callout, StepPicture
from Scripts.GUI.step_pictures import PICTURES


def fixed_measure(text: str, bold: bool) -> tuple[int, int]:
    return (10 * len(text), 40 if bold else 30)


class ExitPointTests(unittest.TestCase):
    def test_arrow_to_the_right_leaves_through_the_right_edge(self) -> None:
        # Arrange
        box = Box(0, 0, 100, 50)

        # Act
        point = annotate.exit_point(box, (300, 25))

        # Assert
        self.assertEqual(point, (100.0, 25.0))

    def test_arrow_downward_leaves_through_the_bottom_edge(self) -> None:
        box = Box(0, 0, 100, 50)

        point = annotate.exit_point(box, (50, 400))

        self.assertEqual(point, (50.0, 50.0))

    def test_target_at_the_center_is_an_error(self) -> None:
        with self.assertRaises(annotate.AnnotateError):
            annotate.exit_point(Box(0, 0, 100, 50), (50, 25))


class ProblemsTests(unittest.TestCase):
    def picture(self, *callouts: Callout, masks: tuple[Box, ...] = ()) -> StepPicture:
        return StepPicture("sample", "main-controllers.png", callouts, masks)

    def test_a_fitting_picture_has_no_problems(self) -> None:
        picture = self.picture(Callout((500, 500), (10, 10), "1. Click", ("Body",)))

        found = annotate.problems(picture, (1000, 1000), fixed_measure)

        self.assertEqual(found, [])

    def test_a_label_past_the_edge_is_reported(self) -> None:
        picture = self.picture(Callout((10, 10), (950, 950), "1. Click"))

        found = annotate.problems(picture, (1000, 1000), fixed_measure)

        self.assertIn("sample: label '1. Click' leaves the picture", found)

    def test_a_target_inside_its_own_label_is_reported(self) -> None:
        picture = self.picture(Callout((20, 20), (10, 10), "1. Click"))

        found = annotate.problems(picture, (1000, 1000), fixed_measure)

        self.assertIn("sample: arrow of '1. Click' ends in its label", found)

    def test_a_mask_past_the_edge_is_reported(self) -> None:
        picture = self.picture(masks=(Box(900, 900, 1100, 950),))

        found = annotate.problems(picture, (1000, 1000), fixed_measure)

        self.assertEqual(len(found), 1)

    def test_the_crop_sets_the_picture_size(self) -> None:
        picture = StepPicture(
            "sample",
            "main-controllers.png",
            (Callout((450, 10), (10, 10), "1. Click"),),
            crop=Box(0, 0, 400, 400),
        )

        found = annotate.problems(picture, (1000, 1000), fixed_measure)

        self.assertIn("sample: arrow of '1. Click' leaves the picture", found)


class ArrowTests(unittest.TestCase):
    def test_the_arrow_ends_at_the_target(self) -> None:
        polygon = annotate.arrow_polygon((0.0, 0.0), (200, 0))

        self.assertIn((200.0, 0.0), polygon)
        self.assertEqual(max(x for x, _ in polygon), 200.0)


class PictureListTests(unittest.TestCase):
    def test_picture_names_are_unique(self) -> None:
        names = [picture.name for picture in PICTURES]

        self.assertEqual(len(names), len(set(names)))

    def test_each_callout_title_starts_with_its_step_number_or_none_does(self) -> None:
        for picture in PICTURES:
            numbered = [c.title[0].isdigit() for c in picture.callouts]
            self.assertIn(set(numbered), (set(), {True}, {False}), picture.name)

    def test_a_picture_without_callouts_hides_something(self) -> None:
        for picture in PICTURES:
            if not picture.callouts:
                self.assertTrue(picture.masks, picture.name)


@unittest.skipUnless(importlib.util.find_spec("PIL"), "Pillow is not installed")
class RenderTests(unittest.TestCase):
    def test_render_masks_and_draws_on_a_capture(self) -> None:
        from PIL import Image

        # Arrange
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "capture.png"
            Image.new("RGBA", (800, 600), (40, 40, 40, 255)).save(source)
            picture = StepPicture(
                "sample",
                source.name,
                (Callout((700, 500), (20, 300), "1. Click Here", ("Then wait.",)),),
                masks=(Box(100, 40, 300, 60),),
            )

            # Act
            image = annotate.render(picture, source)

        # Assert
        self.assertEqual(image.size, (800, 600))
        self.assertEqual(image.getpixel((40, 320))[:3], annotate.RED[:3])

    def test_a_plain_picture_saves_into_its_own_folder(self) -> None:
        from PIL import Image

        # Arrange
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            Image.new("RGBA", (400, 300), (40, 40, 40, 255)).save(root / "main.png")
            plain = StepPicture(
                "main", "main.png", (), masks=(Box(10, 10, 100, 50),), folder=""
            )
            original = annotate.SCREENSHOTS_DIR
            annotate.SCREENSHOTS_DIR = root / "out"
            try:
                with unittest.mock.patch(
                    "Scripts.GUI.step_pictures.PICTURES", (plain,)
                ):
                    # Act
                    code = annotate.main([str(root)])
            finally:
                annotate.SCREENSHOTS_DIR = original

            # Assert
            self.assertEqual(code, 0)
            self.assertTrue((root / "out" / "main.png").is_file())


if __name__ == "__main__":
    unittest.main()
