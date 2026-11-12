from __future__ import annotations

import itertools
import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES_DIRECTORY = Path("Sources/OpenJoystickDriverKit/Resources")
CATALOG_DIRECTORY = Path("Sources/OpenJoystickDriverKit/Resources/en-US.lproj")
CALL = re.compile(
    r"(?:\b(?:OJDLocalized\.(?:string|formatted|plural)|CLILocalized\.(?:text|format|plural)"
    r"|LocalizedStringResource|(?:Localization\(\)|localization)\.(?:string|formatted|plural))"
    r"|\.key)\("
)
KEY_POSITION = re.compile(
    CALL.pattern + r"\s*$|Key\s*:\s*String\s*\{\s*$",
)
EXACT_INTERPOLATIONS = {"error.\\(rawValue).message": r"error\.E\d{4}\.message"}
STRINGS_KEY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=', re.MULTILINE)
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


SEGMENT = r"(?:[a-z][a-zA-Z0-9]*|E\d{4})"
OPERATING_SYSTEMS = ("macos", "windows", "linux")
NAMESPACE_PATTERNS: dict[str, re.Pattern[str]] = {
    "term": re.compile(rf"term(?:\.{SEGMENT})+"),
    "action": re.compile(rf"action(?:\.{SEGMENT})+"),
    "status": re.compile(rf"status(?:\.{SEGMENT})+"),
    "a11y": re.compile(rf"a11y(?:\.{SEGMENT})+"),
    "notify": re.compile(rf"notify(?:\.{SEGMENT})+"),
    "ui": re.compile(rf"ui\.{SEGMENT}(?:\.{SEGMENT})+"),
    "ui.settings": re.compile(rf"ui\.settings\.{SEGMENT}(?:\.{SEGMENT})+"),
    "cli": re.compile(rf"cli\.{SEGMENT}\.{SEGMENT}(?:\.{SEGMENT})+"),
    "error": re.compile(rf"error\.E\d{{4}}(?:\.{SEGMENT})+"),
    "platform": re.compile(
        rf"platform\.(?:{'|'.join(OPERATING_SYSTEMS)})(?:\.{SEGMENT})+"
    ),
}
OS_WORDS = re.compile(
    r"\b(?:DriverKit|macOS|Mac|Apple|System Settings|Login Items|Finder|IOKit|systemextensionsctl"
    r"|launchd|Xcode|Input Monitoring|Privacy & Security|Dock|Terminal|TCC|codesign)\b"
    r"|^Accessibility$|>\s*Accessibility\b|\bAccessibility (?:permission|access)\b"
)
SPECIFIER = re.compile(
    r"%(?P<position>\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfeEgGcCsSpaAF]"
)
COUNT_SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:hh|h|ll|l|q|z|t|j)?[dDiuU]")
NOT_A_COUNT: dict[str, str] = {
    "cli.binding.clear.done": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.binding.clear.dryRun": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.diagnose.group.failed": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.diagnose.group.hidInputDropsFound": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.diagnose.group.recordsApplied": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.diagnose.group.soakErrorInvalidConfiguration": (
        "the numbers are the bounds of a range of the allowed duration and interval"
    ),
    "cli.diagnose.group.soakErrorProcessUnavailable": (
        "the number is the process ID of the service"
    ),
    "cli.diagnose.group.soakVerdictFootprintLimit": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it; the line is a list of measurements"
    ),
    "cli.diagnose.group.soakVerdictInsufficientData": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it; the line is a list of measurements"
    ),
    "cli.diagnose.group.soakVerdictMemoryGrowth": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it; the line is a list of measurements"
    ),
    "cli.diagnose.group.soakVerdictResidentLimit": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it; the line is a list of measurements"
    ),
    "cli.diagnose.group.soakVerdictResourceGrowth": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it; the line is a list of measurements"
    ),
    "cli.diagnose.group.soakVerdictStable": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it; the line is a list of measurements"
    ),
    "cli.diagnose.group.timingsFrame": (
        "the number is a position in a sequence, not a quantity (the frame number)"
    ),
    "cli.diagnose.group.usbOk": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.profile.edit.editorFailed": (
        "the number is a process exit status of the editor"
    ),
    "cli.record.draft.captured": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.record.draft.changedByte": (
        "the numbers are a byte position and two byte values"
    ),
    "cli.record.test.parseFailed": (
        "the number is a position in a sequence, not a quantity (the packet number)"
    ),
    "cli.status.group.labelControllers": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.status.group.labelSkippedVirtualDevices": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.status.group.labelSkippedRecords": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.status.group.labelUnbound": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "cli.transportExtension.group.failed": ("the number is an error code"),
    "platform.macos.cli.status.group.labelPassThrough": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "ui.access.web.enable.port": ("the number is a network port"),
    "ui.access.web.portRange": (
        "the numbers are the bounds of a range of the allowed ports"
    ),
    "ui.capture.touchColumn": (
        "the number is a position in a sequence, not a quantity (the column of a touch cell)"
    ),
    "ui.capture.touchColumns": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "ui.capture.touchRow": (
        "the number is a position in a sequence, not a quantity (the row of a touch cell)"
    ),
    "ui.capture.touchRows": (
        "the number follows its label (after a colon or in parentheses), so no noun agrees with it"
    ),
    "ui.controllers.launch.exited": (
        "the number is a process exit status of the launched program"
    ),
    "ui.developer.soakOutOfRange": (
        "the numbers are the bounds of a range of the allowed value"
    ),
    "ui.inputTest.durationValue": (
        "the number is a duration in milliseconds, written with the unit symbol ms"
    ),
    "ui.mapping.touchGridCell": (
        "the numbers are the size of a touch grid and the position of a cell in it"
    ),
    "ui.profiles.controlNumber": (
        "the number is a position in a sequence, not a quantity (the number that names a control)"
    ),
    "ui.setup.failedDetail": ("the number is an error code"),
}
STRINGS_ENTRY = re.compile(
    r"(?:/\*(?P<comment>(?:(?!\*/).)*)\*/[ \t]*\n?)?"
    r'"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;',
    re.DOTALL,
)
STRINGS_COMMENT = re.compile(r"/\*(?:(?!\*/).)*\*/", re.DOTALL)
STRINGS_KEY_LINE = re.compile(r'"(?P<key>(?:[^"\\]|\\.)*)"\s*=')
STRINGSDICT_COMMENT = re.compile(r"<!--(?:(?!-->).)*-->", re.DOTALL)
STRINGSDICT_KEY = re.compile(r"<key>(?P<key>[^<]+)</key>")
STRINGSDICT_COMMENTED_KEY = re.compile(
    r"(?P<comment><!--(?:(?!-->).)*-->[ \t]*\n)?(?m:^)\t<key>(?P<key>[^<]+)</key>",
    re.DOTALL,
)


@dataclass(frozen=True)
class StringsEntry:
    key: str
    value: str
    comment: str | None


KEPT_WITHOUT_READER: dict[str, str] = {}

NOT_A_KEY: dict[str, str] = {
    "notify.sounds": "the name of a setting that `ojd setting` reads and writes",
}
KEY_SHAPE = re.compile(
    r"(?:term|action|status|ui|a11y|cli|error|notify|platform)(?:\.[A-Za-z0-9_]+)+\.?"
)
FUNCTION_WITH_STRING_PARAMETER = re.compile(
    r"\bfunc\s+(?P<name>\w+)\(\s*_\s+(?P<parameter>\w+)\s*:\s*String\b"
)
PREFIX_HELPER = re.compile(
    r"\bfunc\s+(?P<name>\w+)\(\s*_\s+(?P<parameter>\w+)\s*:\s*String\s*\)\s*->\s*String\s*"
    r'\{\s*(?:return\s+)?OJDLocalized\.string\(\s*"(?P<prefix>[^"\\]+)"\s*\+\s*(?P=parameter)\s*\)'
)


@dataclass(frozen=True)
class KeyUse:
    path: str
    line: int
    expression: str


def skip_string(source: str, index: int) -> int:
    index += 1
    while True:
        character = source[index]
        if character == "\\":
            if source[index + 1] == "(":
                index = skip_group(source, index + 1)
            else:
                index += 2
        elif character == '"':
            return index + 1
        else:
            index += 1


def skip_group(source: str, index: int) -> int:
    depth = 0
    while True:
        character = source[index]
        if character == '"':
            index = skip_string(source, index)
            continue
        if source.startswith("//", index):
            index = source.index("\n", index)
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1


def first_argument(source: str, open_index: int) -> str:
    depth = 0
    index = open_index + 1
    while True:
        character = source[index]
        if character == '"':
            index = skip_string(source, index)
            continue
        if source.startswith("//", index):
            index = source.index("\n", index)
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif character == "," and depth == 0:
            break
        index += 1
    return source[open_index + 1 : index].strip()


def string_literals(source: str) -> list[str]:
    return [text for _, text in string_literal_spans(source)]


def string_literal_spans(source: str) -> list[tuple[int, str]]:
    literals: list[tuple[int, str]] = []
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            newline = source.find("\n", index)
            index = len(source) if newline < 0 else newline
        elif source.startswith("/*", index):
            end = source.find("*/", index + 2)
            index = len(source) if end < 0 else end + 2
        elif source.startswith('"""', index):
            end = source.find('"""', index + 3)
            index = len(source) if end < 0 else end + 3
        elif source.startswith('#"', index):
            end = source.find('"#', index + 2)
            index = len(source) if end < 0 else end + 2
        elif source[index] == '"':
            end = skip_string(source, index)
            literals.append((index, source[index + 1 : end - 1]))
            index = end
        else:
            index += 1
    return literals


def interpolation_pattern(literal: str) -> re.Pattern[str] | None:
    if "\\(" not in literal or "." not in literal.split("\\(")[0]:
        return None
    if literal in EXACT_INTERPOLATIONS:
        return re.compile(EXACT_INTERPOLATIONS[literal])
    pattern = ""
    index = 0
    while index < len(literal):
        if literal.startswith("\\(", index):
            pattern += "[^.]+"
            index = skip_group(literal, index + 1)
        else:
            pattern += re.escape(literal[index])
            index += 1
    return re.compile(pattern)


def key_arguments(source: str) -> list[tuple[int, str]]:
    return [
        (
            source.count("\n", 0, match.start()) + 1,
            first_argument(source, match.end() - 1),
        )
        for match in CALL.finditer(source)
    ]


def catalog_keys(root: Path = ROOT) -> set[str]:
    directory = root / CATALOG_DIRECTORY
    strings = (directory / "Localizable.strings").read_text(encoding="utf-8")
    keys = set(STRINGS_KEY.findall(strings))
    keys.update(plistlib.loads((directory / "Localizable.stringsdict").read_bytes()))
    return keys


def problems(expression: str, keys: set[str]) -> str | None:
    literals = LITERAL.findall(expression)
    if re.fullmatch(r'"[^"\\]*"', expression):
        return None if literals[0] in keys else f"missing key {literals[0]!r}"
    ternary = re.search(r'\?\s*"([^"\\]*)"\s*:\s*"([^"\\]*)"', expression)
    if ternary:
        absent = [key for key in ternary.groups() if key not in keys]
        return f"missing key {absent[0]!r}" if absent else None
    prefix = re.match(r'"([^"\\]*)(?:\\\(|"\s*\+)', expression)
    if prefix and prefix.group(1):
        if any(key.startswith(prefix.group(1)) for key in keys):
            return None
        return f"no key starts with {prefix.group(1)!r}"
    return None


def key_literal_problems(source: str, keys: set[str]) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    for offset, literal in string_literal_spans(source):
        if (
            KEY_SHAPE.fullmatch(literal)
            and literal not in keys
            and literal not in NOT_A_KEY
            and not any(key.startswith(literal) for key in keys)
        ):
            found.append((source.count("\n", 0, offset) + 1, literal))
    return found


def helper_key_problems(source: str, keys: set[str]) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    functions = list(FUNCTION_WITH_STRING_PARAMETER.finditer(source))
    for helper in PREFIX_HELPER.finditer(source):
        names = {helper["name"]}
        for index, function in enumerate(functions):
            end = (
                functions[index + 1].start()
                if index + 1 < len(functions)
                else len(source)
            )
            body = source[function.end() : end]
            if re.search(rf"\b{helper['name']}\(\s*{function['parameter']}\s*\)", body):
                names.add(function["name"])
        for name in sorted(names):
            for call in re.finditer(rf'(?<!func )\b{name}\(\s*"([^"\\]*)"', source):
                key = helper["prefix"] + call[1]
                if key not in keys:
                    found.append((source.count("\n", 0, call.start()) + 1, key))
    return found


def tracked_swift_files(root: Path = ROOT) -> list[Path]:
    output = subprocess.run(
        [
            "git",
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "*.swift",
        ],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [
        root / name for name in output.split("\0") if name and (root / name).exists()
    ]


def reader_files(root: Path = ROOT) -> list[Path]:
    return [
        path
        for path in tracked_swift_files(root)
        if path.relative_to(root).parts[0] == "Sources"
    ]


def key_readers(root: Path = ROOT) -> tuple[set[str], dict[str, re.Pattern[str]]]:
    literals: set[str] = set()
    patterns: dict[str, re.Pattern[str]] = {}
    for path in reader_files(root):
        source = path.read_text(encoding="utf-8")
        for offset, literal in string_literal_spans(source):
            pattern = interpolation_pattern(literal)
            if pattern:
                line = source[source.rfind("\n", 0, offset) + 1 : offset]
                if KEY_POSITION.search(line):
                    patterns[literal] = pattern
            elif "\\(" not in literal:
                literals.add(literal)
    for literal in literals:
        if literal.endswith((".", "_")) and len(literal) > 3:
            patterns[f"{literal} + <text>"] = re.compile(re.escape(literal) + ".+")
    return literals, patterns


def unread_keys(root: Path = ROOT) -> tuple[list[str], dict[str, int]]:
    keys = catalog_keys(root)
    literals, patterns = key_readers(root)
    unread: list[str] = []
    covered: dict[str, int] = {}
    for key in sorted(keys):
        if key in literals:
            continue
        matching = [
            text for text, pattern in patterns.items() if pattern.fullmatch(key)
        ]
        for text in matching:
            covered[text] = covered.get(text, 0) + 1
        if not matching:
            unread.append(key)
    return unread, covered


def stale_kept(unread: list[str], keys: set[str]) -> list[str]:
    return [
        f"kept key {key!r} "
        + ("is not in the catalog" if key not in keys else "has a reader")
        for key in sorted(KEPT_WITHOUT_READER)
        if key not in keys or key not in unread
    ]


def strings_entries(text: str) -> list[StringsEntry]:
    return [
        StringsEntry(
            match["key"],
            match["value"],
            match["comment"].strip() if match["comment"] is not None else None,
        )
        for match in STRINGS_ENTRY.finditer(text)
    ]


def duplicate_keys(entries: list[StringsEntry]) -> list[str]:
    seen: set[str] = set()
    found: list[str] = []
    for entry in entries:
        if entry.key in seen and entry.key not in found:
            found.append(entry.key)
        seen.add(entry.key)
    return found


def locale_directories(root: Path = ROOT) -> list[Path]:
    return sorted((root / RESOURCES_DIRECTORY).glob("*.lproj"))


def language(directory: Path) -> str:
    return directory.name.removesuffix(".lproj").split("-")[0]


def key_shape_problem(key: str) -> str | None:
    for namespace in ("ui.settings", "ui"):
        if key.startswith(namespace + "."):
            pattern = NAMESPACE_PATTERNS[namespace]
            return (
                None
                if pattern.fullmatch(key)
                else f"key {key!r} breaks the {namespace}. shape"
            )
    pattern = NAMESPACE_PATTERNS.get(key.split(".")[0])
    if pattern is None:
        return f"key {key!r} is outside the namespaces"
    return (
        None
        if pattern.fullmatch(key)
        else f"key {key!r} breaks the {key.split('.')[0]}. shape"
    )


def os_word_problem(key: str, value: str) -> str | None:
    word = OS_WORDS.search(value)
    if word is None or key.startswith("platform."):
        return None
    return f"{key!r}: the value names {word[0]!r} outside platform."


def specifier_problem(key: str, value: str) -> str | None:
    specifiers = [m for m in SPECIFIER.finditer(value.replace("%%", ""))]
    if len(specifiers) > 1 and any(m["position"] is None for m in specifiers):
        return f"{key!r}: several format specifiers need positions (%1$@)"
    return None


def comment_problem(entry: StringsEntry) -> str | None:
    return None if entry.comment else f"{entry.key!r}: no translator comment"


def comment_specifier_problem(entry: StringsEntry) -> str | None:
    specifiers = list(SPECIFIER.finditer(entry.value.replace("%%", "")))
    if not specifiers or entry.comment is None:
        return None
    names = [f"%{m['position']}" for m in specifiers if m["position"]] or ["%"]
    missing = [name for name in names if name not in entry.comment]
    if not missing:
        return None
    return f"{entry.key!r}: the comment does not name {', '.join(missing)}"


def comment_copy_problems(
    entries: list[StringsEntry], english: list[StringsEntry]
) -> list[tuple[str, str]]:
    expected = {entry.key: entry.comment for entry in english}
    found = {entry.key: entry.comment for entry in entries}
    problems = [
        (key, f"{key!r}: the key is not in the en-US strings")
        for key in found
        if key not in expected
    ]
    for key, comment in expected.items():
        if key not in found:
            problems.append((key, f"{key!r}: the key is missing"))
        elif found[key] != comment:
            problems.append(
                (key, f"{key!r}: the comment differs from the en-US comment")
            )
    return problems


def stacked_comment_keys(
    text: str, comment: re.Pattern[str], key: re.Pattern[str]
) -> list[str]:
    spans = [match.span() for match in comment.finditer(text)]
    found: list[str] = []
    for (_, end), (start, _) in itertools.pairwise(spans):
        if text[end:start].strip():
            continue
        following = key.search(text, start)
        name = following["key"] if following else "(end of file)"
        if name not in found:
            found.append(name)
    return found


def stacked_comment_problems(directory: Path) -> list[RuleProblem]:
    problems: list[RuleProblem] = []
    for name, comment, key in (
        ("Localizable.strings", STRINGS_COMMENT, STRINGS_KEY_LINE),
        ("Localizable.stringsdict", STRINGSDICT_COMMENT, STRINGSDICT_KEY),
    ):
        text = (directory / name).read_text(encoding="utf-8")
        for stacked in stacked_comment_keys(text, comment, key):
            problems.append(
                RuleProblem(
                    stacked,
                    f"{directory.name}/{name}: {stacked!r} has more than one comment above it",
                )
            )
    return problems


def stringsdict_uncommented_keys(root: Path = ROOT) -> set[str]:
    text = (root / CATALOG_DIRECTORY / "Localizable.stringsdict").read_text(
        encoding="utf-8"
    )
    matches = list(STRINGSDICT_COMMENTED_KEY.finditer(text))
    top_level = set(plistlib.loads(text.encode("utf-8")))
    if {match["key"] for match in matches} != top_level:
        raise ValueError(
            "the en-US stringsdict has top-level keys the comment scan does not match: "
            f"{sorted(top_level ^ {match['key'] for match in matches})}"
        )
    return {match["key"] for match in matches if not match["comment"]}


def stringsdict_values(root: Path = ROOT) -> dict[str, list[str]]:
    plurals = plistlib.loads(
        (root / CATALOG_DIRECTORY / "Localizable.stringsdict").read_bytes()
    )
    return {
        key: [
            text
            for item in entry.values()
            for text in ([item] if isinstance(item, str) else item.values())
            if isinstance(text, str)
        ]
        for key, entry in plurals.items()
    }


@dataclass(frozen=True)
class RuleProblem:
    key: str
    message: str


def count_specifier_problem(
    entry: StringsEntry, plurals: set[str], not_a_count: dict[str, str] | None = None
) -> str | None:
    if (
        entry.key in plurals
        or entry.key in (NOT_A_COUNT if not_a_count is None else not_a_count)
        or not COUNT_SPECIFIER.search(entry.value.replace("%%", ""))
    ):
        return None
    return (
        f"{entry.key!r}: an integer specifier needs a stringsdict entry, "
        "or a NOT_A_COUNT reason"
    )


def not_a_count_problem(
    key: str, entries: list[StringsEntry], plurals: set[str]
) -> str | None:
    entry = next((e for e in entries if e.key == key), None)
    if entry is None:
        return f"{key!r}: NOT_A_COUNT names a key that is not in the en-US strings"
    if key in plurals:
        return f"{key!r}: NOT_A_COUNT names a key that has a stringsdict entry"
    if not COUNT_SPECIFIER.search(entry.value.replace("%%", "")):
        return f"{key!r}: NOT_A_COUNT names a value without an integer specifier"
    return None


def rule_problems(
    root: Path = ROOT, not_a_count: dict[str, str] | None = None
) -> dict[str, list[RuleProblem]]:
    not_a_count = NOT_A_COUNT if not_a_count is None else not_a_count
    found: dict[str, list[RuleProblem]] = {
        "namespace": [],
        "osWord": [],
        "specifier": [],
        "comment": [],
        "pluralCount": [],
        "stackedComment": [],
        "commentSpecifier": [],
        "commentCopy": [],
        "duplicateKey": [],
    }

    def add(rule: str, key: str, message: str | None, prefix: str = "") -> None:
        if message:
            found[rule].append(RuleProblem(key, prefix + message))

    directory = root / CATALOG_DIRECTORY
    entries = strings_entries((directory / "Localizable.strings").read_text("utf-8"))
    plurals = plistlib.loads((directory / "Localizable.stringsdict").read_bytes())
    uncommented = stringsdict_uncommented_keys(root)
    for entry in entries:
        add("namespace", entry.key, key_shape_problem(entry.key))
        add("osWord", entry.key, os_word_problem(entry.key, entry.value))
        add("specifier", entry.key, specifier_problem(entry.key, entry.value))
        add("comment", entry.key, comment_problem(entry))
        add("commentSpecifier", entry.key, comment_specifier_problem(entry))
        add(
            "pluralCount",
            entry.key,
            count_specifier_problem(entry, set(plurals), not_a_count),
        )
    for key in sorted(not_a_count):
        add("pluralCount", key, not_a_count_problem(key, entries, set(plurals)))
    for key, texts in stringsdict_values(root).items():
        add("namespace", key, key_shape_problem(key))
        for text in texts:
            add("specifier", key, specifier_problem(key, text))
        if key in uncommented:
            add("comment", key, f"{key!r}: no translator comment in the stringsdict")
    for name in ("C",):
        for entry in strings_entries(
            (
                root / RESOURCES_DIRECTORY / f"{name}.lproj" / "Localizable.strings"
            ).read_text("utf-8")
        ):
            add(
                "osWord",
                entry.key,
                os_word_problem(entry.key, entry.value),
                f"{name}.lproj ",
            )
    for locale in locale_directories(root):
        found["stackedComment"].extend(stacked_comment_problems(locale))
        text = (locale / "Localizable.strings").read_text(encoding="utf-8")
        locale_entries = strings_entries(text)
        for key in duplicate_keys(locale_entries):
            add(
                "duplicateKey",
                key,
                f"{key!r} is defined more than once",
                f"{locale.name}: ",
            )
        if locale.name == "en-US.lproj":
            continue
        for entry in locale_entries:
            add(
                "specifier",
                entry.key,
                specifier_problem(entry.key, entry.value),
                f"{locale.name}: ",
            )
        for key, message in comment_copy_problems(locale_entries, entries):
            add("commentCopy", key, message, f"{locale.name}: ")
    return found


def rule_report(found: dict[str, list[RuleProblem]]) -> list[str]:
    return [p.message for problems in found.values() for p in problems]


def check(root: Path = ROOT) -> tuple[list[tuple[KeyUse, str]], list[KeyUse]]:
    keys = catalog_keys(root)
    missing: list[tuple[KeyUse, str]] = []
    unscannable: list[KeyUse] = []
    for path in tracked_swift_files(root):
        relative = path.relative_to(root).as_posix()
        source = path.read_text(encoding="utf-8")
        for line, expression in key_arguments(source):
            use = KeyUse(relative, line, expression)
            reason = problems(expression, keys)
            if reason:
                missing.append((use, reason))
            elif not LITERAL.search(expression):
                unscannable.append(use)
        reported = {
            (use.line, reason) for use, reason in missing if use.path == relative
        }
        for line, key in key_literal_problems(source, keys) + helper_key_problems(
            source, keys
        ):
            reason = f"missing key {key!r}"
            if (line, reason) not in reported:
                reported.add((line, reason))
                missing.append((KeyUse(relative, line, key), reason))
    return missing, unscannable


def main(arguments: list[str] | None = None) -> int:
    if arguments:
        print("usage: check_localization_keys.py", file=sys.stderr)
        return 2
    missing, unscannable = check()
    unread, covered = unread_keys()
    unexplained = [key for key in unread if key not in KEPT_WITHOUT_READER]
    stale = stale_kept(unread, catalog_keys())
    failing = rule_report(rule_problems())
    for problem in failing:
        print(problem)
    for use, reason in missing:
        print(f"{use.path}:{use.line}: {reason} in the en-US catalog")
    for use in unscannable:
        print(f"{use.path}:{use.line}: key not scanned: {use.expression}")
    for key in unexplained:
        print(f"{key}: no Swift source reads this catalog key")
    for problem in stale:
        print(problem)
    for key, reason in KEPT_WITHOUT_READER.items():
        print(f"kept without reader: {key}: {reason}")
    for text, count in sorted(covered.items()):
        print(f"read by pattern: {text} ({count} keys)")
    if missing or unexplained or stale or failing:
        print(
            f"error: {len(missing)} key(s) missing from en-US, {len(unexplained)} "
            f"key(s) with no reader, {len(stale)} stale kept entr(ies), "
            f"{len(failing)} catalog rule violation(s)",
            file=sys.stderr,
        )
        return 1
    print("Every scannable localization key used in Swift exists in the en-US catalog.")
    print("Every en-US catalog key is read by Swift or kept with a reason.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
