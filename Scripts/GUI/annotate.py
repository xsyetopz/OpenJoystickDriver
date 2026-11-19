"""Draw red step callouts and privacy masks on window captures for the wiki.

Each picture in `Scripts.GUI.step_pictures` names a window capture made by
`just shots-capture`, the boxes to mask, and the callouts to draw. Coordinates are
pixels of the capture after its optional crop, with the origin at the top left.
"""

from __future__ import annotations

import argparse
import math
import sys
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from PIL import Image as PILImage

PROJECT_DIR = Path(__file__).resolve().parents[2]
STEPS_DIR = PROJECT_DIR / "docs" / "screenshots" / "steps"
FONT_FILE = "/System/Library/Fonts/Helvetica.ttc"
FONT_REGULAR = 0
FONT_BOLD = 1
RED = (230, 30, 30, 255)
WHITE = (255, 255, 255, 255)
TITLE_SIZE = 34
BODY_SIZE = 28
LINE_GAP = 6
PADDING = 18
RADIUS = 18
OUTLINE = 4
SHAFT = 8
HEAD_LENGTH = 34
HEAD_WIDTH = 30
# Large blocks first, then a blur, so no letter shape of a masked name survives.
MASK_BLOCK = 24
MASK_BLUR = 10

Point = tuple[int, int]
Measure = Callable[[str, bool], tuple[int, int]]


class AnnotateError(Exception):
    pass


@dataclass(frozen=True)
class Box:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def center(self) -> tuple[float, float]:
        return ((self.left + self.right) / 2, (self.top + self.bottom) / 2)

    def contains(self, point: Point) -> bool:
        x, y = point
        return self.left <= x <= self.right and self.top <= y <= self.bottom

    def inside(self, width: int, height: int) -> bool:
        return (
            0 <= self.left < self.right <= width
            and 0 <= self.top < self.bottom <= height
        )


@dataclass(frozen=True)
class Callout:
    """A red label at `at` (its top-left corner) with an arrow to `target`."""

    target: Point
    at: Point
    title: str
    body: tuple[str, ...] = ()


@dataclass(frozen=True)
class StepPicture:
    """One annotated picture: `docs/screenshots/steps/<name>.png`."""

    name: str
    source: str
    callouts: tuple[Callout, ...]
    masks: tuple[Box, ...] = ()
    crop: Box | None = None


def label_box(callout: Callout, measure: Measure) -> Box:
    widths_heights = [measure(callout.title, True)] + [
        measure(line, False) for line in callout.body
    ]
    width = max(width for width, _ in widths_heights) + 2 * PADDING
    height = (
        sum(height for _, height in widths_heights)
        + LINE_GAP * (len(widths_heights) - 1)
        + 2 * PADDING
    )
    left, top = callout.at
    return Box(left, top, left + width, top + height)


def exit_point(box: Box, target: Point) -> tuple[float, float]:
    """Return where the line from the box's center to `target` leaves the box."""
    cx, cy = box.center
    dx, dy = target[0] - cx, target[1] - cy
    if dx == 0 and dy == 0:
        raise AnnotateError(f"arrow target {target} is the center of its label")
    half_width, half_height = (box.right - box.left) / 2, (box.bottom - box.top) / 2
    scale = min(
        half_width / abs(dx) if dx else math.inf,
        half_height / abs(dy) if dy else math.inf,
    )
    return (cx + dx * scale, cy + dy * scale)


def problems(
    picture: StepPicture, size: tuple[int, int], measure: Measure
) -> list[str]:
    """List each callout, mask, or crop of `picture` that does not fit `size`."""
    width, height = size
    found: list[str] = []
    if picture.crop is not None:
        if not picture.crop.inside(width, height):
            found.append(f"{picture.name}: crop {picture.crop} leaves the capture")
        width = picture.crop.right - picture.crop.left
        height = picture.crop.bottom - picture.crop.top
    for mask in picture.masks:
        if not mask.inside(width, height):
            found.append(f"{picture.name}: mask {mask} leaves the picture")
    for callout in picture.callouts:
        box = label_box(callout, measure)
        if not box.inside(width, height):
            found.append(f"{picture.name}: label {callout.title!r} leaves the picture")
        if not Box(0, 0, width, height).contains(callout.target):
            found.append(
                f"{picture.name}: arrow of {callout.title!r} leaves the picture"
            )
        if box.contains(callout.target):
            found.append(
                f"{picture.name}: arrow of {callout.title!r} ends in its label"
            )
    return found


def arrow_polygon(start: tuple[float, float], tip: Point) -> list[tuple[float, float]]:
    """Return the arrow as one polygon: shaft from `start`, head ending at `tip`."""
    dx, dy = tip[0] - start[0], tip[1] - start[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = -uy, ux
    base = (tip[0] - ux * HEAD_LENGTH, tip[1] - uy * HEAD_LENGTH)
    half_shaft, half_head = SHAFT / 2, HEAD_WIDTH / 2
    return [
        (start[0] + nx * half_shaft, start[1] + ny * half_shaft),
        (base[0] + nx * half_shaft, base[1] + ny * half_shaft),
        (base[0] + nx * half_head, base[1] + ny * half_head),
        (float(tip[0]), float(tip[1])),
        (base[0] - nx * half_head, base[1] - ny * half_head),
        (base[0] - nx * half_shaft, base[1] - ny * half_shaft),
        (start[0] - nx * half_shaft, start[1] - ny * half_shaft),
    ]


def render(picture: StepPicture, source: Path) -> PILImage.Image:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    fonts = {
        True: ImageFont.truetype(FONT_FILE, TITLE_SIZE, index=FONT_BOLD),
        False: ImageFont.truetype(FONT_FILE, BODY_SIZE, index=FONT_REGULAR),
    }

    def measure(text: str, bold: bool) -> tuple[int, int]:
        width = fonts[bold].getlength(text)
        return (math.ceil(width), int(fonts[bold].getmetrics()[0] + 4))

    image = Image.open(source).convert("RGBA")
    if picture.crop is not None:
        crop = picture.crop
        image = image.crop((crop.left, crop.top, crop.right, crop.bottom))
    found = problems(picture, image.size, measure)
    if found:
        raise AnnotateError("\n".join(found))
    for mask in picture.masks:
        area = (mask.left, mask.top, mask.right, mask.bottom)
        region = image.crop(area)
        small = region.resize(
            (
                max(1, region.width // MASK_BLOCK),
                max(1, region.height // MASK_BLOCK),
            ),
            Image.Resampling.BILINEAR,
        )
        blocks = small.resize(region.size, Image.Resampling.NEAREST)
        image.paste(blocks.filter(ImageFilter.GaussianBlur(MASK_BLUR)), area)
    draw = ImageDraw.Draw(image)
    for callout in picture.callouts:
        box = label_box(callout, measure)
        polygon = arrow_polygon(exit_point(box, callout.target), callout.target)
        draw.polygon(polygon, fill=RED, outline=WHITE, width=OUTLINE // 2)
    for callout in picture.callouts:
        box = label_box(callout, measure)
        draw.rounded_rectangle(
            (box.left, box.top, box.right, box.bottom),
            RADIUS,
            fill=RED,
            outline=WHITE,
            width=OUTLINE,
        )
        y = box.top + PADDING
        for text, bold in [(callout.title, True)] + [
            (line, False) for line in callout.body
        ]:
            draw.text((box.left + PADDING, y), text, font=fonts[bold], fill=WHITE)
            y += measure(text, bold)[1] + LINE_GAP
    return image


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="just shots-annotate",
        description=(
            "Draw the step callouts and privacy masks of Scripts/GUI/step_pictures.py "
            "on the window captures of one just shots-capture folder."
        ),
    )
    parser.add_argument("captures", type=Path, help="a folder under .ojd-shots")
    parser.add_argument(
        "--only", action="append", metavar="NAME", help="annotate only this picture"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=STEPS_DIR,
        help="folder for the annotated pictures (default docs/screenshots/steps)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    from Scripts.GUI.step_pictures import PICTURES

    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        import PIL  # noqa: F401
    except ImportError:
        print(
            "error: Pillow is not installed: python3 -m pip install pillow",
            file=sys.stderr,
        )
        return 1
    chosen = [p for p in PICTURES if not args.only or p.name in args.only]
    unknown = set(args.only or ()) - {p.name for p in PICTURES}
    if unknown:
        print(f"error: no picture named {', '.join(sorted(unknown))}", file=sys.stderr)
        return 2
    args.output.mkdir(parents=True, exist_ok=True)
    failed = 0
    for picture in chosen:
        source = args.captures / picture.source
        if not source.is_file():
            print(f"error: {picture.name}: no capture {source}", file=sys.stderr)
            failed += 1
            continue
        try:
            image = render(picture, source)
        except AnnotateError as error:
            print(f"error: {error}", file=sys.stderr)
            failed += 1
            continue
        destination = args.output / f"{picture.name}.png"
        image.save(destination, optimize=True)
        print(destination)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
