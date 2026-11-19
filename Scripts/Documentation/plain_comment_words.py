"""Swap jargon for everyday words in Swift doc comments.

Only `///` comment prose changes. Code, inline code in backticks, and DocC symbol links stay as
they are, because they name real identifiers. Each swap keeps the meaning in every context the
repository uses it in; words whose meaning depends on context stay for a person to rewrite.

Usage: python3 Scripts/Documentation/plain_comment_words.py [--check] <path>...
"""

import argparse
import pathlib
import re
import sys

SWAPS: list[tuple[str, str]] = [
    (r"\breturns? to neutral\b", lambda m: m.group(0).replace("neutral", "rest")),
    (r"\bto neutral\b", "to rest"),
    (r"\bis neutral\b", "is at rest"),
    (r"\bare neutral\b", "are at rest"),
    (r"\bleaves neutral\b", "leaves centre"),
    (r"\bneutral by default\b", "at rest by default"),
    (r"\b(from|against) neutral\b", r"\1 rest"),
    (r"\b(reads|not) neutral\b", r"\1 at rest"),
    (r"\bnone for neutral\b", "none at rest"),
    (r"\baround neutral\b", "around the rest point"),
    (r"\bneutral then\b", "rest then"),
    (r"\band neutral the\b", "and at rest the"),
    (r"\bneutral case\b", "at-rest case"),
    (r"\ba neutral\b", "an at-rest"),
    (r"\bA neutral\b", "An at-rest"),
    (r"(?<!-)\bneutral\b", "at-rest"),
    (r"\bemitted\b", "sent"),
    (r"\bemits\b", "sends"),
    (r"\bemit\b", "send"),
    (r"\bEmits\b", "Sends"),
    (r"\bdispatches\b", "sends"),
    (r"\bdispatched\b", "sent"),
    (r"\bDispatches\b", "Sends"),
    (r"\bpersisted\b", "saved"),
    (r"\bpersists\b", "saves"),
    (r"\bmonotonic\b", "forward-only"),
    (r"\bidempotent\b", "safe to repeat"),
    (r"\bholds the (device|controller) exclusively\b", r"holds the \1 for itself"),
]

DOC = re.compile(r"^(\s*///)(.*)$")


def swap_prose(text: str) -> str:
    """Apply each swap to the parts of a comment that sit outside backticks."""
    parts = re.split(r"(``[^`]*``|`[^`]*`)", text)
    for index in range(0, len(parts), 2):
        for pattern, replacement in SWAPS:
            parts[index] = re.sub(pattern, replacement, parts[index])
    return "".join(parts)


def rewrite(source: str) -> str:
    """Return the source with every doc comment line rewritten."""
    lines = source.split("\n")
    for number, line in enumerate(lines):
        match = DOC.match(line)
        if match:
            lines[number] = match.group(1) + swap_prose(match.group(2))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check", action="store_true", help="list files that would change"
    )
    parser.add_argument("paths", nargs="+", type=pathlib.Path)
    args = parser.parse_args()
    files = [
        p
        for root in args.paths
        for p in ([root] if root.is_file() else root.rglob("*.swift"))
    ]
    changed = 0
    for path in files:
        before = path.read_text()
        after = rewrite(before)
        if after != before:
            changed += 1
            if args.check:
                print(path)
            else:
                path.write_text(after)
    print(
        f"{changed} files {'would change' if args.check else 'changed'}",
        file=sys.stderr,
    )
    return 1 if args.check and changed else 0


if __name__ == "__main__":
    sys.exit(main())
