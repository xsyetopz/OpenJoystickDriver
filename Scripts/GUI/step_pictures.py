"""The annotated wiki pictures `just shots-annotate` draws.

Each source is a window capture from `just shots-capture --all`. Masks hide what the public
should not see: the apps that hold a controller open and the device addresses in the log.
"""

from __future__ import annotations

from Scripts.GUI.annotate import Box, Callout, StepPicture

PICTURES: tuple[StepPicture, ...] = (
    StepPicture(
        "main-controllers",
        "main-controllers.png",
        (),
        masks=(Box(800, 835, 1886, 936),),
        folder="",
    ),
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
                (390, 717),
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
            Callout(
                (1330, 1212),
                (30, 1130),
                "Handled by: who reads it",
                ("macOS, or OJD with a virtual gamepad.",),
            ),
        ),
        masks=(Box(800, 835, 1886, 936),),
    ),
    StepPicture(
        "virtual-gamepad-kind",
        "main-popup.png",
        (
            Callout(
                (1440, 956),
                (20, 860),
                "Automatic (start here)",
                ("OJD picks the kind for this model.",),
            ),
            Callout(
                (1440, 1004),
                (20, 970),
                "For Steam and SDL games",
                ("Steam, SDL games, emulators.",),
            ),
            Callout(
                (1440, 1051),
                (20, 1080),
                "Generic HID gamepad",
                ("A plain gamepad. Games can't rumble it.",),
            ),
            Callout(
                (1440, 1099),
                (20, 1190),
                "For Apple Game Controller games",
                ("Safari and apps that use GameController.",),
            ),
        ),
        masks=(Box(800, 320, 1886, 395),),
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
        "access-overview",
        "main-access.png",
        (
            Callout(
                (1800, 70),
                (1000, 90),
                "Grant a Program... or Create a Token...",
                ("Let in one signed app, or make a", "password for a script."),
            ),
            Callout(
                (1690, 336),
                (1000, 300),
                "Allowed: macOS said yes",
                ("Each row says what OJD uses it for.",),
            ),
            Callout(
                (1760, 563),
                (380, 800),
                "Two doors for your programs",
                (
                    "Local endpoint: programs on this Mac.",
                    "WebSocket: web pages with a token.",
                    "Both stay off until you turn them on.",
                ),
            ),
            Callout(
                (1700, 735),
                (1150, 830),
                "Port",
                ("Automatic: the system picks", "a free port."),
            ),
        ),
    ),
    StepPicture(
        "profile-editor",
        "main-profiles.png",
        (
            Callout(
                (1430, 175),
                (370, 235),
                "Set Active",
                ("Turns the profile on", "for its controller model."),
            ),
            Callout(
                (1345, 290),
                (370, 420),
                "Profile editor section",
                ("Assignments, Combinations,", "Layers, Macros, Controller."),
            ),
            Callout(
                (814, 534),
                (370, 600),
                "Controller control",
                ("What you press.", "Here, A / Cross."),
            ),
            Callout(
                (1106, 660),
                (1000, 705),
                "Destination: what the Mac gets",
                ("Here, B / Circle gets Escape.",),
            ),
            Callout(
                (1838, 392),
                (1240, 335),
                "+ adds an assignment",
                ("One rule: press this, get that.",),
            ),
            Callout(
                (1635, 956),
                (370, 800),
                "Behavior...",
                ("How a press acts:", "Hold, Toggle, and more."),
            ),
            Callout(
                (1672, 1240),
                (1050, 1192),
                "Save keeps your changes",
                ("Saved means nothing is waiting.",),
            ),
        ),
    ),
    StepPicture(
        "profile-controller-section",
        "main-profiles-controller.png",
        (
            Callout(
                (1400, 300),
                (380, 290),
                "Choose Controller here",
                ("It holds the stick, trigger,", "touch, and motion settings."),
            ),
            Callout(
                (1838, 960),
                (1060, 1000),
                "The pencil opens a group",
                ("Stick Modes, Trigger Stages, and more.", "Scroll down for the rest."),
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
