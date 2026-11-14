from __future__ import annotations

import re
import sys
from pathlib import Path

from Scripts.Quality.check_localization_keys import (
    CATALOG_DIRECTORY,
    RESOURCES_DIRECTORY,
    ROOT,
    StringsEntry,
    locale_directories,
    strings_entries,
    stringsdict_values,
)

GLOSSARY = Path("wiki/Glossary.md")
WIKI_DIRECTORY = Path("wiki")
WIKI_SKIPPED = {"Glossary.md", "AGENTS.md", "_Sidebar.md", "_Footer.md"}
GLOSSARY_LINK = "Glossary.md#terms"
QUOTED = re.compile(r'"([^"]+)"')
KEPT: dict[str, str] = {
    "cli.transportExtension.group.bundleMissing": "%@.dext names the bundle file",
    "error.E1004.message": (
        "transport names the socket and the WebSocket of the endpoint, not how a controller reaches the Mac"
    ),
    "error.E5007.modes.interfaceRawUSB": "transport names the usb transport key of a record",
    "error.E5007.protocolDescription.activationTransport": (
        "transport names an entry of the writeTransports key"
    ),
    "error.E5007.startupWrite.transport": "transport names the key of a startup write",
    "error.E5007.virtualDevice.bundledMissing": "persona names the key of the file",
    "error.E5007.virtualDevice.bundledPersona": "persona names the key of the file",
    "error.E5007.virtualDevice.definition": "persona and transport name keys of the file",
    "error.E5007.virtualDevice.matchExtras": "transport names the key of the file",
    "error.E5007.virtualDevice.persona": "persona names the key of the file",
    "error.E5007.virtualDevice.transport": "transport names the key of the file",
}
WIKI_KEPT: dict[tuple[str, str], str] = {
    ("Building-from-Source.md", "virtual device"): "names the entitlement of that name",
    ("Building-from-Source.md", "DriverKit"): "quotes the message of the build tool",
    ("Controller-Records.md", "transport"): "names the transport key of a record",
    ("Error-Codes.md", "transport"): "names the socket and WebSocket of the endpoint",
    ("Known-Issues.md", "transport"): "names the Transport property macOS reports",
    ("Playing-Games.md", "transport"): "names the Transport property macOS reports",
    (
        "Start-Set-Up-Several-Macs.md",
        "system extension",
    ): "titles an Apple support article",
}
KIND_KEYS = re.compile(
    r"^(?:platform\.macos\.)?ui\.virtualProfile\.(?:title|kind\.(?!withIdentifier$))"
)
KIND_IDENTIFIERS = ("SDLCompatible", "GameControllerCompatible", "Generic")
CONNECTION_TITLES = (
    "cli.controller.show.labelConnection",
    "ui.library.field.transport",
)
PAD_LEFT_TO_MACOS = "platform.macos.ui.controllers.servedByMacOS"


def glossary_terms(text: str) -> dict[str, list[str]]:
    terms: dict[str, list[str]] = {}
    section = text.split("## Terms", 1)[1].split("\n## ", 1)[0]
    rows = [line for line in section.splitlines() if line.startswith("|")]
    for line in rows[2:]:
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        terms[cells[0]] = [
            item[1:-1] for item in cells[2].split(", ") if QUOTED.fullmatch(item)
        ]
    return terms


def word_pattern(word: str) -> re.Pattern[str]:
    return re.compile(rf"(?<![\w-]){re.escape(word)}(?![\w-])", re.IGNORECASE)


def replaced_word_problems(
    entries: list[StringsEntry], terms: dict[str, list[str]], kept: dict[str, str]
) -> list[str]:
    patterns = [
        (word, term, word_pattern(word))
        for term, words in terms.items()
        for word in words
    ]
    problems: list[str] = []
    holding: set[str] = set()
    for entry in entries:
        for word, term, pattern in patterns:
            if pattern.search(entry.value):
                holding.add(entry.key)
                if entry.key not in kept:
                    problems.append(f"{entry.key!r}: {word!r} replaced by {term!r}")
    keys = {entry.key for entry in entries}
    for key in sorted(kept):
        if key not in keys:
            problems.append(f"kept key {key!r} is not in the en-US strings")
        elif key not in holding:
            problems.append(f"kept key {key!r} holds no replaced word")
    return problems


def normalized(value: str) -> str:
    return value.rstrip(":：").strip().casefold()


def term_anchors(english: list[StringsEntry], terms: list[str]) -> dict[str, list[str]]:
    anchors = {
        term: [
            entry.key for entry in english if normalized(entry.value) == term.casefold()
        ]
        for term in terms
    }
    return {term: keys for term, keys in anchors.items() if keys}


def translation_problems(
    entries: list[StringsEntry], anchors: dict[str, list[str]]
) -> list[str]:
    values = {entry.key: entry.value for entry in entries}
    problems: list[str] = []
    for term, keys in anchors.items():
        translations: dict[str, list[str]] = {}
        for key in keys:
            translations.setdefault(normalized(values[key]), []).append(key)
        if len(translations) > 1:
            listed = ", ".join(
                f"{values[found[0]]!r} ({', '.join(found)})"
                for found in translations.values()
            )
            problems.append(f"{term!r} has {len(translations)} translations: {listed}")
    return problems


def wiki_prose(text: str) -> str:
    """Return the text of a wiki page without code, headings, bold labels, and images."""
    for pattern, flags in (
        (r"```.*?```", re.DOTALL),
        (r"`[^`]*`", 0),
        (r"^#.*$", re.MULTILINE),
        (r"\*\*[^*]+\*\*", 0),
        (r"!\[[^\]]*\]\([^)]*\)", 0),
    ):
        text = re.sub(pattern, "", text, flags=flags)
    return re.sub(r"\[([^\]]*)\]\((?!Glossary\.md)[^)]*\)", r"\1", text)


def wiki_pages(root: Path) -> dict[str, str]:
    return {
        page.name: wiki_prose(page.read_text(encoding="utf-8"))
        for page in sorted((root / WIKI_DIRECTORY).glob("*.md"))
        if page.name not in WIKI_SKIPPED
    }


def wiki_replaced_word_problems(
    pages: dict[str, str], terms: dict[str, list[str]], kept: dict[tuple[str, str], str]
) -> list[str]:
    problems: list[str] = []
    holding: set[tuple[str, str]] = set()
    for page, text in pages.items():
        for term, words in terms.items():
            for word in words:
                if word_pattern(word).search(text):
                    holding.add((page, word))
                    if (page, word) not in kept:
                        problems.append(f"{page}: {word!r} replaced by {term!r}")
    problems += [
        f"kept wiki word {key} is not in the page"
        for key in sorted(kept)
        if key not in holding
    ]
    return problems


def wiki_first_use_problems(pages: dict[str, str], terms: list[str]) -> list[str]:
    """A term of more than one word links to the glossary at its first use on a page."""
    longest_first = sorted(
        (term for term in terms if " " in term), key=len, reverse=True
    )
    problems: list[str] = []
    for page, text in pages.items():
        taken: set[int] = set()
        for term in longest_first:
            found = [
                match
                for match in re.finditer(
                    rf"(?<![\w-]){re.escape(term)}(?:s|es)?(?![\w-])",
                    text,
                    re.IGNORECASE,
                )
                if match.start() not in taken
            ]
            taken |= {match.start() for match in found}
            if found and not text[found[0].end() :].startswith(f"]({GLOSSARY_LINK})"):
                problems.append(
                    f"{page}: first use of {term!r} does not link to {GLOSSARY_LINK}"
                )
    return problems


def term_string_problems(root: Path = ROOT) -> list[str]:
    glossary = (root / GLOSSARY).read_text(encoding="utf-8")
    english = strings_entries(
        (root / CATALOG_DIRECTORY / "Localizable.strings").read_text(encoding="utf-8")
    )
    values = {entry.key: entry.value for entry in english}
    problems: list[str] = []
    for key, value in values.items():
        if KIND_KEYS.match(key):
            problems += [
                f"{key!r}: the virtual gamepad kind control shows {word!r}"
                for word in ("profile", "persona")
                if word_pattern(word).search(value)
            ]
            if value in KIND_IDENTIFIERS:
                problems.append(
                    f"{key!r}: an option is titled with the identifier {value!r}"
                )
    problems += [
        f"{key!r}: reads {values[key]!r}, not 'Connection'"
        for key in CONNECTION_TITLES
        if values[key] != "Connection"
    ]
    entry = next(
        line for line in glossary.splitlines() if line.startswith("| Handled by macOS")
    )
    if values[PAD_LEFT_TO_MACOS] != "Handled by macOS" or "`System`" not in entry:
        problems.append(
            f"{PAD_LEFT_TO_MACOS!r} and the glossary do not tie 'Handled by macOS' to System"
        )
    return problems


def scan(root: Path = ROOT, kept: dict[str, str] | None = None) -> list[str]:
    glossary = (root / GLOSSARY).read_text(encoding="utf-8")
    terms = glossary_terms(glossary)
    english = strings_entries(
        (root / CATALOG_DIRECTORY / "Localizable.strings").read_text(encoding="utf-8")
    )
    plurals = [
        StringsEntry(key, text, None)
        for key, texts in stringsdict_values(root).items()
        for text in texts
    ]
    report = replaced_word_problems(
        english + plurals, terms, KEPT if kept is None else kept
    )
    pages = wiki_pages(root)
    report += wiki_replaced_word_problems(
        pages, terms, WIKI_KEPT if kept is None else {}
    )
    report += wiki_first_use_problems(pages, list(terms))
    anchors = term_anchors(english, list(terms))
    for locale in locale_directories(root):
        entries = strings_entries(
            (locale / "Localizable.strings").read_text(encoding="utf-8")
        )
        report += [
            f"{locale.name}: {problem}"
            for problem in translation_problems(entries, anchors)
        ]
    return report


def main(arguments: list[str] | None = None) -> int:
    if arguments:
        print("usage: python3 -m Scripts.Quality.check_glossary_terms", file=sys.stderr)
        return 2
    report = scan() + term_string_problems()
    for entry in report:
        print(entry)
    if report:
        print(f"error: {len(report)} glossary term violation(s)", file=sys.stderr)
        return 1
    print(
        f"No en-US string holds a word that {GLOSSARY} replaces, "
        f"and each bundle under {RESOURCES_DIRECTORY} translates each term one way."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
