"""Draw the real output of one `ojd` command as a Terminal window for the wiki.

The picture shows a plain `$` prompt and a fixed title instead of a screenshot of
Terminal, so no user name, host name, or folder reaches the wiki. The output is the
installed `ojd`'s, run with color off.
"""

from __future__ import annotations

import argparse
import math
import os
import shlex
import subprocess
import sys
from collections.abc import Sequence

from Scripts.GUI.capture import make_folder

FONT_FILE = "/System/Library/Fonts/Menlo.ttc"
FONT_SIZE = 26
TITLE_FONT_FILE = "/System/Library/Fonts/Helvetica.ttc"
TITLE_SIZE = 26
TITLE = "Terminal"
PROMPT = "$ "
# Pixel sizes at 2x, the scale of the app window captures the callouts are drawn for.
TITLE_BAR = 56
MARGIN = 28
LINE_GAP = 8
RADIUS = 20
MIN_COLUMNS = 60
# Terminal wraps a longer line at the window edge; 100 columns keeps the picture readable.
MAX_COLUMNS = 100
LIGHTS = ((255, 95, 87), (254, 188, 46), (40, 200, 64))
LIGHT_RADIUS = 12
LIGHT_SPACING = 40
BACKGROUND = (255, 255, 255)
TITLE_BACKGROUND = (236, 236, 236)
BORDER = (200, 200, 200)
TEXT = (30, 30, 30)
TITLE_TEXT = (90, 90, 90)


def run_ojd(arguments: Sequence[str]) -> list[str]:
    """The lines `ojd` prints on standard output and standard error, in order."""
    environment = {**os.environ, "NO_COLOR": "1", "OJD_COLOR": "never"}
    result = subprocess.run(
        ["ojd", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=environment,
        check=False,
    )
    return result.stdout.rstrip("\n").splitlines()


def render(command: str, lines: Sequence[str]):
    from PIL import Image, ImageDraw, ImageFont

    font = ImageFont.truetype(FONT_FILE, FONT_SIZE)
    title_font = ImageFont.truetype(TITLE_FONT_FILE, TITLE_SIZE)
    text = [
        line[start : start + MAX_COLUMNS]
        for line in [PROMPT + command, *lines]
        for start in range(0, max(1, len(line)), MAX_COLUMNS)
    ]
    advance = font.getlength("M")
    columns = max(MIN_COLUMNS, *(len(line) for line in text))
    line_height = sum(font.getmetrics()) + LINE_GAP
    width = math.ceil(columns * advance) + 2 * MARGIN
    height = TITLE_BAR + 2 * MARGIN + line_height * len(text)
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        (0, 0, width - 1, height - 1), RADIUS, fill=BACKGROUND, outline=BORDER, width=2
    )
    draw.rounded_rectangle(
        (1, 1, width - 2, TITLE_BAR),
        RADIUS,
        fill=TITLE_BACKGROUND,
        corners=(True, True, False, False),
    )
    draw.line((0, TITLE_BAR, width, TITLE_BAR), fill=BORDER, width=2)
    for index, color in enumerate(LIGHTS):
        center = (MARGIN + LIGHT_RADIUS + index * LIGHT_SPACING, TITLE_BAR // 2)
        draw.ellipse(
            (
                center[0] - LIGHT_RADIUS,
                center[1] - LIGHT_RADIUS,
                center[0] + LIGHT_RADIUS,
                center[1] + LIGHT_RADIUS,
            ),
            fill=color,
        )
    draw.text(
        (width / 2, TITLE_BAR / 2), TITLE, font=title_font, fill=TITLE_TEXT, anchor="mm"
    )
    y = TITLE_BAR + MARGIN
    for line in text:
        draw.text((MARGIN, y), line, font=font, fill=TEXT)
        y += line_height
    return image


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="just shots-terminal",
        description="Draw one ojd command and its output as a Terminal window in a new .ojd-shots folder.",
    )
    parser.add_argument("name", help="file name of the picture, without .png")
    parser.add_argument(
        "arguments", nargs=argparse.REMAINDER, help="the ojd arguments, such as status"
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not args.arguments:
        print("error: name the ojd arguments, such as: status", file=sys.stderr)
        return 64
    command = shlex.join(["ojd", *args.arguments])
    destination = make_folder() / f"{args.name}.png"
    render(command, run_ojd(args.arguments)).save(destination)
    print(destination)
    return 0


if __name__ == "__main__":
    sys.exit(main())
