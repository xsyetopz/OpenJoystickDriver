"""The annotated wiki pictures `just shots-annotate` draws.

Each source is a window capture from `just shots-capture --all`. Masks hide what the public
should not see: the apps that hold a controller open and the device addresses in the log.
"""

from __future__ import annotations

from Scripts.GUI.annotate import Box, Callout, StepPicture

PICTURES: tuple[StepPicture, ...] = (
    StepPicture(
        "controllers-overview",
        "main-controllers.png",
        (
            Callout(
                (365, 300),
                (12, 450),
                "Pick a controller",
                ("Each row shows its", "name and status."),
            ),
            Callout(
                (1760, 304),
                (1240, 150),
                "Open Input Test",
                ("Press each button and watch it light up.",),
            ),
            Callout(
                (390, 860),
                (30, 960),
                "Needs a step from you",
                ("Do what the text above it says.",),
            ),
            Callout(
                (940, 805),
                (1150, 842),
                "Opened by: apps using it now",
                ("Blurred here for privacy.",),
            ),
        ),
        masks=(Box(800, 835, 1886, 936),),
    ),
    StepPicture(
        "menu-bar-overview",
        "menu-status-item.png",
        (
            Callout(
                (612, 168),
                (30, 15),
                "One row per controller",
                ("Point at one to pick a profile,", "pause it, or test it."),
            ),
            Callout(
                (330, 540),
                (100, 575),
                "Quit stops OpenJoystickDriver",
                ("Games lose their virtual gamepads.",),
            ),
        ),
    ),
    StepPicture(
        "library-overview",
        "main-library.png",
        (
            Callout(
                (1320, 88),
                (800, 170),
                "Library buttons, left to right",
                (
                    "Add a record or mod from a file",
                    "Check a file without installing it",
                    "Test the record on a packet capture",
                    "Remove the selected record or mod",
                ),
            ),
            Callout(
                (645, 178),
                (360, 560),
                "Installed or Built-in",
                ("Your files, or the ones that ship with the app.",),
            ),
        ),
    ),
    StepPicture(
        "activity-overview",
        "main-activity.png",
        (
            Callout(
                (1040, 88),
                (880, 220),
                "Log or Diagnostics",
                ("Log: what happened.", "Diagnostics: run checks."),
            ),
            Callout(
                (1810, 88),
                (1350, 400),
                "Copy, Save, Show in Finder",
                ("Share the log in a bug report.",),
            ),
        ),
        masks=(Box(990, 180, 1885, 1290),),
    ),
    StepPicture(
        "profiles-toolbar",
        "main-profiles.png",
        (
            Callout(
                (1670, 88),
                (1010, 170),
                "Profile buttons, left to right",
                (
                    "New profile for a controller",
                    "Import a profile file",
                    "Check a file without importing it",
                    "Copy, change model, save to file, delete",
                ),
            ),
        ),
    ),
    StepPicture(
        "settings-interface",
        "settings-general.png",
        (
            Callout(
                (1112, 866),
                (330, 890),
                "Interface",
                (
                    "All Controls shows every tool.",
                    "Simple hides the advanced ones.",
                ),
            ),
        ),
    ),
    StepPicture(
        "install-command-line-tool",
        "settings-advanced.png",
        (
            Callout(
                (950, 335),
                (60, 880),
                "Install Command-Line Tool",
                (
                    "Lets you type ojd in Terminal.",
                    "macOS asks for your password.",
                ),
            ),
        ),
    ),
)
