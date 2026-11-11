"""Capture windows of the installed app into a git-ignored folder."""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from Scripts.Quality import repository_tool

PROJECT_DIR = Path(__file__).resolve().parents[2]
GUI_DIR = Path(__file__).resolve().parent
APP = Path("/Applications/OpenJoystickDriver.app")
PROCESS = "OpenJoystickDriver"
BUNDLE_ID = "com.openjoystickdriver"
AREAS = ("Controllers", "Profiles", "Library", "Access", "Activity")
SETTINGS_PANES = ("General", "Notifications", "Advanced")
BOUNDS_TOLERANCE = 2.0
# kCGDockWindowLevel and kCGMainMenuWindowLevel: the Dock and the menu bar. kCGCursorWindowLevel:
# the pointer, which screencapture leaves out of the image without -C.
SCREEN_CHROME_LAYERS = (20, 24, 2147483630)
ACCESSIBILITY_GRANTED = "0"
ACCESSIBILITY_NOT_TRUSTED = "-25211"
ACCESSIBILITY_CANNOT_COMPLETE = "-25204"
# AXError -25204 is the app not answering Accessibility requests yet. No signal reports
# that the app answers: finished launching does not imply it, and an AXObserver needs an
# element that answers. Readiness is therefore polled, bounded by this deadline.
APP_READY_TIMEOUT_SECONDS = 15.0
APP_READY_POLL_SECONDS = 0.25
# After the app is activated and its window raised, the window list needs a moment to show
# nothing in front of it. No signal reports that, so the list is polled until this deadline.
FRONT_TIMEOUT_SECONDS = 5.0
FRONT_POLL_SECONDS = 0.25
# kCGPopUpMenuWindowLevel: the layer of every open menu and submenu window.
MENU_LAYER = 101
# An open menu is on screen once the app owns exactly as many menu windows as menus are open,
# and stable once two window lists in a row show the same menu windows at the same bounds and
# alpha, so a menu that still moves or fades is not captured.
MENU_TIMEOUT_SECONDS = 5.0
MENU_POLL_SECONDS = 0.1
MENU_STABLE_READS = 2
# Escape closes the innermost open menu: the deepest capture holds three menus, so four presses
# leave one to spare. After each press the menu windows are read until one fewer is open.
ESCAPE_PRESSES = 4
ESCAPE_SETTLE_SECONDS = 1.0
# Menus are found by AXIdentifier, which the app sets from its Swift menu model ids
# (MainMenuModel.menuBarItemIdentifier, MainMenuModel item ids, StatusItemModel entry ids), so
# the menu capture does not depend on the UI language.
MENU_BAR_ID_PREFIX = "menu."
PROFILE_MENU_ID = "menu.profile"
ACTIVATE_PROFILE_ID = "activateProfile"


class CaptureError(Exception):
    pass


@dataclass(frozen=True)
class MenuTarget:
    """One menu capture: the file name stem and the AXIdentifiers of the menu bar item and
    of the submenu items to open.

    `status_item` selects the app's status item instead of a main menu bar item; its `path`
    then holds only submenu items. `depth` is the number of menus open at the end.
    """

    name: str
    path: tuple[str, ...]
    status_item: bool = False

    @property
    def depth(self) -> int:
        return len(self.path) + (1 if self.status_item else 0)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./Scripts/ojd shots capture",
        description=(
            "Capture the screen rectangle of each app window with screencapture -R "
            "into .ojd-shots/<timestamp>/."
        ),
    )
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--area", choices=AREAS, help="sidebar area of the main window")
    choice.add_argument(
        "--settings-pane", choices=SETTINGS_PANES, help="tab of the Settings window"
    )
    choice.add_argument(
        "--menus",
        action="store_true",
        help=(
            "every main menu, the Activate Profile submenu and the status item menu, "
            "each with its open submenu in one image"
        ),
    )
    choice.add_argument(
        "--all",
        action="store_true",
        help="every sidebar area, settings pane and menu",
    )
    parser.add_argument(
        "--ready-timeout",
        type=float,
        default=APP_READY_TIMEOUT_SECONDS,
        metavar="SECONDS",
        help=(
            "longest wait, in seconds, for the app to answer Accessibility requests "
            f"(default {APP_READY_TIMEOUT_SECONDS:g})"
        ),
    )
    parser.add_argument(
        "--front-timeout",
        type=float,
        default=FRONT_TIMEOUT_SECONDS,
        metavar="SECONDS",
        help=(
            "longest wait, in seconds, for no other window to cover a captured window "
            f"after the app is brought forward (default {FRONT_TIMEOUT_SECONDS:g})"
        ),
    )
    args = parser.parse_args(argv)
    for option, value in (
        ("--ready-timeout", args.ready_timeout),
        ("--front-timeout", args.front_timeout),
    ):
        if not math.isfinite(value) or value <= 0:
            parser.error(
                f"{option} must be a finite number of seconds greater than zero"
            )
    return args


def run(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = result.stderr.strip()
        if f"AXError {ACCESSIBILITY_NOT_TRUSTED}" in detail:
            raise CaptureError(not_trusted_message(ACCESSIBILITY_NOT_TRUSTED))
        raise CaptureError(f"{' '.join(command[:3])} failed: {detail}")
    return result.stdout.strip()


def ax(command: str, pid: int, *args: str) -> str:
    script = str(GUI_DIR / "ax.js")
    return run(["osascript", "-l", "JavaScript", script, command, str(pid), *args])


def gui(command: str, *args: str) -> str:
    return ax(command, process_id(), *args)


def session_state() -> str:
    script = str(GUI_DIR / "ax.js")
    return run(["osascript", "-l", "JavaScript", script, "session"])


def require_unlocked_console_session() -> None:
    """A locked or background session hides app windows from Accessibility and capture."""
    reported = session_state()
    found = re.fullmatch(r"locked=(true|false) console=(true|false)", reported)
    if not found:
        raise CaptureError(f"session state reported {reported!r}")
    if found.group(1) == "true":
        raise CaptureError(
            "the screen is locked: unlock this Mac's session and run the capture "
            "again; macOS hides app windows from Accessibility and screen capture "
            "while it is locked"
        )
    if found.group(2) == "false":
        raise CaptureError(
            "this login session is not on the console: switch to it and run the "
            "capture again; macOS hides app windows from Accessibility and screen "
            "capture in a session that is not on the console"
        )


def process_id() -> int:
    if not APP.is_dir():
        raise CaptureError(f"{APP} is not installed: ./Scripts/ojd build install dev")
    result = subprocess.run(
        ["pgrep", "-f", f"{APP}/Contents/MacOS/{PROCESS}$"],
        capture_output=True,
        text=True,
        check=False,
    )
    # pgrep exits 0 when it found a process, 1 when none matched, and 2 or 3 on an error.
    if result.returncode == 1:
        raise CaptureError(f"{PROCESS} is not running: open {APP}")
    if result.returncode != 0:
        raise CaptureError(
            f"pgrep failed with exit status {result.returncode}: {result.stderr.strip()}"
        )
    pids = result.stdout.split()
    if len(pids) != 1:
        raise CaptureError(
            f"{len(pids)} {PROCESS} processes run from {APP} (pids {', '.join(pids)}): "
            "quit all but one and run the capture again"
        )
    return int(pids[0])


def not_trusted_message(code: str) -> str:
    return (
        f"Accessibility is not granted to the host app (AXError {code}): "
        "allow the host app in System Settings > Privacy & Security > "
        "Accessibility"
    )


def require_accessibility(
    pid: int,
    timeout: float = APP_READY_TIMEOUT_SECONDS,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    """Reads the app role through the Accessibility API and names each failure.

    AXError -25204 means the app does not answer yet, so only that code is waited on,
    until `timeout` seconds have passed on `clock`. Every other code fails at once.
    """
    deadline = clock() + timeout
    while True:
        code = ax("probe", pid)
        if code == ACCESSIBILITY_GRANTED:
            return
        if code == ACCESSIBILITY_NOT_TRUSTED:
            raise CaptureError(not_trusted_message(code))
        if code != ACCESSIBILITY_CANNOT_COMPLETE:
            raise CaptureError(
                f"Accessibility call to {PROCESS} failed (AXError {code}) although "
                "the host app is trusted: the app may not be responding, or the "
                "command is not running in a logged-in GUI session"
            )
        if clock() >= deadline:
            raise CaptureError(
                f"{PROCESS} did not answer Accessibility requests within "
                f"{timeout:g} s (last AXError {code}): wait for the app to "
                "finish launching and run the capture again, or raise "
                "--ready-timeout"
            )
        sleep(min(APP_READY_POLL_SECONDS, max(0.0, deadline - clock())))


def on_screen_windows() -> list[dict]:
    """Every on-screen window, front to back, as window-list.js reports it."""
    listing = run(["osascript", "-l", "JavaScript", str(GUI_DIR / "window-list.js")])
    return json.loads(listing)


def find_window(pid: int, kind: str, windows: list[dict]) -> dict:
    """The app window of `kind`: the on-screen layer-0 window of `pid` at its AX bounds."""
    reported = gui("window-bounds", kind)
    try:
        bounds = [float(value) for value in reported.split()]
    except ValueError as error:
        raise CaptureError(f"window-bounds reported {reported!r}") from error
    if len(bounds) != 4:
        raise CaptureError(f"window-bounds reported {reported!r}, expected x y w h")
    for window in windows:
        if window["pid"] != pid or window["layer"] != 0:
            continue
        found = [window[key] for key in ("x", "y", "width", "height")]
        if all(abs(a - b) <= BOUNDS_TOLERANCE for a, b in zip(found, bounds)):
            return window
    raise CaptureError(f"no on-screen {kind} window has bounds {bounds}")


def overlaps(first: dict, second: dict) -> bool:
    return (
        first["x"] < second["x"] + second["width"]
        and second["x"] < first["x"] + first["width"]
        and first["y"] < second["y"] + second["height"]
        and second["y"] < first["y"] + first["height"]
    )


def covering_windows(target: dict, windows: list[dict]) -> list[str]:
    """Owners of the windows in front of `target` that overlap it.

    `windows` is front to back. The Dock and the menu bar are transparent windows over the
    whole screen in front of every app window, and the pointer is not in the image, so their
    layers are not counted.
    """
    front = windows[: next(i for i, w in enumerate(windows) if w["id"] == target["id"])]
    return [
        window["owner"]
        for window in front
        if window["layer"] not in SCREEN_CHROME_LAYERS and overlaps(window, target)
    ]


def without_other_menus(
    menu: dict, menus: list[dict], windows: list[dict]
) -> list[dict]:
    """`windows`, front to back, without the menus of the capture other than `menu`: the
    menus the capture opened overlap one another and all belong in the image."""
    others = {other["id"] for other in menus if other["id"] != menu["id"]}
    return [window for window in windows if window["id"] not in others]


def screen_rectangle(window: dict) -> str:
    """The `screencapture -R` argument for the window's frame in global points."""
    values = [window[key] for key in ("x", "y", "width", "height")]
    return ",".join(f"{value:g}" for value in values)


def require_english_ui() -> None:
    """The sidebar and Settings scripts click English labels, so another UI language is
    refused. The menu capture finds menus by AXIdentifier and needs no English."""
    for domain in (BUNDLE_ID, "-g"):
        result = subprocess.run(
            ["defaults", "read", domain, "AppleLanguages"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            languages = re.findall(r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*", result.stdout)
            if languages and languages[0].lower().startswith("en"):
                return
            first = languages[0] if languages else "none"
            raise CaptureError(
                f"the app UI language is {first} ({domain}): the sidebar and Settings "
                "captures match English labels; put English first in System Settings > "
                "General > Language & Region, or capture only --menus"
            )
    raise CaptureError("AppleLanguages is unset: cannot tell the app UI language")


def read_state() -> tuple[bool, str | None]:
    """Whether the main window is open and which Settings tab is open, if any."""
    reported = gui("app-state")
    found = re.fullmatch(r"main=(true|false) settings=(\S+)", reported)
    if not found:
        raise CaptureError(f"app-state reported {reported!r}")
    tab = None if found.group(2) == "none" else found.group(2)
    if tab is not None and tab not in SETTINGS_PANES:
        raise CaptureError(f"the open Settings window shows unknown tab {tab!r}")
    return found.group(1) == "true", tab


def covered_message(subject: str, covering: list[str], waited: str) -> str:
    return (
        f"{subject} is covered by windows of {', '.join(sorted(set(covering)))} "
        f"{waited}: move them off and run the capture again"
    )


def bring_forward(
    pid: int,
    kind: str,
    timeout: float = FRONT_TIMEOUT_SECONDS,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> dict:
    """Activates the app, raises its `kind` window and returns it once nothing covers it.

    The raise is repeated on every read of the window list, until `timeout` seconds have
    passed on `clock`. A window that is still covered then fails by the owners of the
    windows in front of it: a covered window is never captured.
    """
    deadline = clock() + timeout
    while True:
        gui("raise", kind)
        windows = on_screen_windows()
        window = find_window(pid, kind, windows)
        covering = covering_windows(window, windows)
        if not covering:
            return window
        if clock() >= deadline:
            raise CaptureError(
                covered_message(
                    f"the {kind} window",
                    covering,
                    f"after {timeout:g} s of bringing the app forward (--front-timeout)",
                )
            )
        sleep(min(FRONT_POLL_SECONDS, max(0.0, deadline - clock())))


def capture_rectangle(window: dict, destination: Path) -> None:
    """Writes the screen rectangle of `window` to `destination`."""
    run(["screencapture", "-x", "-R", screen_rectangle(window), str(destination)])
    if not destination.is_file() or destination.stat().st_size == 0:
        raise CaptureError(
            f"screencapture wrote no image to {destination}: grant Screen Recording"
        )


def shoot(
    pid: int,
    kind: str,
    destination: Path,
    timeout: float = FRONT_TIMEOUT_SECONDS,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    """Captures the screen rectangle of the window, so its materials show what lies behind.

    `screencapture -l` draws one window alone over transparency: a Liquid Glass or other
    translucent surface then has no backdrop and comes out washed out over a checkerboard.
    The rectangle shows whatever is in front of the window too, so the app is brought
    forward first and a window that stays covered fails.
    """
    capture_rectangle(bring_forward(pid, kind, timeout, clock, sleep), destination)
    print(destination)


def menu_slug(identifier: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", identifier.lower()).strip("-")


def menu_targets(ids: list[str]) -> list[MenuTarget]:
    """The menu captures in order: each main menu in menu bar order, the Activate Profile
    submenu right after the Profile menu, then the status item menu and its Activate submenu.

    `ids` are the AXIdentifiers of the main menu bar items after the Apple menu, as
    `ax.js menu-ids` reports them. An identifier without the `menu.` prefix, identifiers that
    give the same file name, and a menu bar without a Profile menu are refused.
    """
    for identifier in ids:
        if not identifier.startswith(MENU_BAR_ID_PREFIX):
            raise CaptureError(
                f"main menu bar item {identifier!r} has no {MENU_BAR_ID_PREFIX!r} identifier"
            )
    if PROFILE_MENU_ID not in ids:
        raise CaptureError(
            f"the main menu bar has no {PROFILE_MENU_ID} menu (found {ids or 'none'})"
        )
    targets: list[MenuTarget] = []
    for identifier in ids:
        name = f"menu-{menu_slug(identifier.removeprefix(MENU_BAR_ID_PREFIX))}"
        targets.append(MenuTarget(name, (identifier,)))
        if identifier == PROFILE_MENU_ID:
            targets.append(
                MenuTarget(
                    f"{name}-activate-profile", (identifier, ACTIVATE_PROFILE_ID)
                )
            )
    targets.append(MenuTarget("menu-status-item", (), status_item=True))
    names = [target.name for target in targets]
    for name in sorted(set(names)):
        if names.count(name) > 1:
            raise CaptureError(f"two menus give the capture name {name}")
    return targets


def open_menu_command(target: MenuTarget) -> tuple[str, ...]:
    if target.status_item:
        return ("open-status-menu", *target.path)
    return ("open-menu", *target.path)


def menu_windows(pid: int, windows: list[dict]) -> list[dict]:
    """The open menu and submenu windows of the app, front to back."""
    return [
        window
        for window in windows
        if window["pid"] == pid and window["layer"] == MENU_LAYER
    ]


def union_rectangle(windows: list[dict]) -> dict:
    """The smallest rectangle that holds every window, as a window of its own."""
    if not windows:
        raise CaptureError("no window to take a rectangle from")
    left = min(window["x"] for window in windows)
    top = min(window["y"] for window in windows)
    right = max(window["x"] + window["width"] for window in windows)
    bottom = max(window["y"] + window["height"] for window in windows)
    return {"x": left, "y": top, "width": right - left, "height": bottom - top}


def mask_tool() -> Path:
    """The built `OJDRepositoryTool`, which masks a menu capture in Swift."""
    try:
        return repository_tool.binary()
    except repository_tool.ToolError as error:
        raise CaptureError(str(error)) from error


def keep_menu_windows(menus: list[dict], frame: dict, destination: Path) -> None:
    """Makes every pixel of the `frame` capture outside all menu windows transparent.

    The union rectangle of a parent menu and its submenu, or of a status menu, holds screen
    beside the menus that can show another app. `OJDRepositoryTool mask-image` keeps each menu
    window's whole bounds, its rounded corners and their shadow pixels included.
    """
    run(
        [
            str(mask_tool()),
            "mask-image",
            str(destination),
            screen_rectangle(frame),
            *(screen_rectangle(menu) for menu in menus),
        ]
    )


def menu_signature(windows: list[dict]) -> list[tuple]:
    return sorted(
        (w["id"], w["x"], w["y"], w["width"], w["height"], w["alpha"]) for w in windows
    )


def wait_for_menu(
    pid: int,
    depth: int,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> tuple[list[dict], list[dict]]:
    """Waits until exactly `depth` menu windows are on screen and unchanged over two reads.

    More menu windows than `depth` are never taken as the menu: they would add a menu that
    the capture did not open. Returns the menu windows and the window list they came from.
    """
    deadline = clock() + MENU_TIMEOUT_SECONDS
    previous: list[tuple] | None = None
    stable = 0
    while True:
        windows = on_screen_windows()
        menus = menu_windows(pid, windows)
        signature = menu_signature(menus)
        if len(menus) == depth:
            stable = stable + 1 if signature == previous else 1
            if stable >= MENU_STABLE_READS:
                return menus, windows
        else:
            stable = 0
        previous = signature
        if clock() >= deadline:
            raise CaptureError(
                f"{len(menus)} menu windows of {PROCESS} were on screen where {depth} "
                f"were opened, or they did not stay still, within "
                f"{MENU_TIMEOUT_SECONDS:g} s"
            )
        sleep(MENU_POLL_SECONDS)


def close_menu(
    pid: int,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    """Presses Escape until the app has no open menu window, at most ESCAPE_PRESSES times.

    Escape is only posted while a menu of the app is on screen, so it reaches the menu and
    not a window. After each press the window list is read until fewer menus are open, for at
    most ESCAPE_SETTLE_SECONDS, before the next press.
    """
    for _ in range(ESCAPE_PRESSES):
        before = len(menu_windows(pid, on_screen_windows()))
        if before == 0:
            return
        gui("press-escape")
        deadline = clock() + ESCAPE_SETTLE_SECONDS
        while clock() < deadline:
            if len(menu_windows(pid, on_screen_windows())) < before:
                break
            sleep(MENU_POLL_SECONDS)
    if menu_windows(pid, on_screen_windows()):
        raise CaptureError(
            f"a menu of {PROCESS} is still open after {ESCAPE_PRESSES} Escape presses"
        )


def shoot_menu(
    pid: int,
    target: MenuTarget,
    destination: Path,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    """Opens the menu through the Accessibility API, captures the union rectangle of its
    open menu windows (a parent menu and its open submenu in one image) with every pixel
    outside the menu windows transparent, then closes it.

    A menu of the app that is open before the capture opens one is refused, because its
    window would join the image. A menu that a window covers fails like a covered window. A
    close that fails after another failure is printed and the first failure is raised.
    """
    already_open = menu_windows(pid, on_screen_windows())
    if already_open:
        raise CaptureError(
            f"{len(already_open)} menu windows of {PROCESS} are open before the "
            f"{target.name} capture: close the menu and run the capture again"
        )
    try:
        gui(*open_menu_command(target))
        menus, windows = wait_for_menu(pid, target.depth, clock, sleep)
        # A submenu overlaps its parent menu, and both belong in the image.
        covering = [
            owner
            for menu in menus
            for owner in covering_windows(
                menu, without_other_menus(menu, menus, windows)
            )
        ]
        if covering:
            raise CaptureError(
                covered_message(f"the {target.name} menu", covering, "once it opened")
            )
        frame = union_rectangle(menus)
        capture_rectangle(frame, destination)
        keep_menu_windows(menus, frame, destination)
        print(destination)
    except CaptureError:
        try:
            close_menu(pid, clock, sleep)
        except CaptureError as error:
            print(f"error: close {target.name}: {error}", file=sys.stderr)
        raise
    close_menu(pid, clock, sleep)


def make_folder() -> Path:
    root = PROJECT_DIR / ".ojd-shots"
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    root.mkdir(exist_ok=True)
    for counter in range(1000):
        folder = root / (stamp if counter == 0 else f"{stamp}-{counter}")
        try:
            folder.mkdir()
        except FileExistsError:
            continue
        return folder
    raise CaptureError(f"no free capture folder for {stamp} in {root}")


def restore(steps: list[tuple[str, tuple[str, ...]]]) -> list[str]:
    """Runs every step, reports each failure to stderr and returns the failures."""
    failures = []
    for label, command in steps:
        try:
            gui(*command)
        except (CaptureError, OSError) as error:
            failures.append(label)
            print(f"error: restore {label}: {error}", file=sys.stderr)
    return failures


def capture(args: argparse.Namespace) -> int:
    pid = process_id()
    require_unlocked_console_session()
    require_accessibility(pid, args.ready_timeout)
    areas = AREAS if args.all else (args.area,) if args.area else ()
    panes = (
        SETTINGS_PANES
        if args.all
        else (args.settings_pane,)
        if args.settings_pane
        else ()
    )
    menus = args.all or args.menus
    if areas or panes:
        require_english_ui()
    if menus:
        # Built before any menu opens, so no build runs while a menu waits on screen.
        mask_tool()
    main_was_open, settings_tab = read_state()
    folder = make_folder()
    sidebar = None
    opens_settings = False
    try:
        run(["open", str(APP)])
        gui("wait-main-window")
        sidebar = gui("current-sidebar")
        for area in areas:
            gui("select-sidebar", area)
            shoot(pid, "main", folder / f"main-{area.lower()}.png", args.front_timeout)
        for pane in panes:
            opens_settings = settings_tab is None
            gui("open-settings", pane)
            shoot(
                pid,
                "settings",
                folder / f"settings-{pane.lower()}.png",
                args.front_timeout,
            )
        if menus:
            for target in menu_targets(gui("menu-ids").split("\n")):
                shoot_menu(pid, target, folder / f"{target.name}.png")
    finally:
        steps: list[tuple[str, tuple[str, ...]]] = []
        if sidebar is not None:
            steps.append(("sidebar area", ("select-sidebar", sidebar)))
        if settings_tab is not None and panes:
            steps.append(("settings tab", ("open-settings", settings_tab)))
        if opens_settings:
            steps.append(("settings window", ("close-window", "settings")))
        if not main_was_open:
            steps.append(("main window", ("close-window", "main")))
        failures = restore(steps)
    return 2 if failures else 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return capture(args)
    except CaptureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
