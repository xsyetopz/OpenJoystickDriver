"""Convert the flat `docs/` pages into GitHub wiki pages."""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
DOCS = ROOT / "docs"
DEFAULT_REPOSITORY = "xsyetopz/OpenJoystickDriver"
EXCLUDED_FILES = frozenset({"AGENTS.md"})
EXCLUDED_DIRECTORIES = frozenset({"external"})
INLINE_LINK = re.compile(r"(\]\()([^)\s]+)")
REFERENCE_DEFINITION = re.compile(r"^( {0,3}\[[^\]]+\]:[ \t]+)(\S+)", re.MULTILINE)
FENCE = re.compile(r"^ {0,3}(```|~~~)")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


class WikiBuildError(RuntimeError):
    pass


def page_files(docs: pathlib.Path) -> list[pathlib.Path]:
    """Return the pages to publish, and reject layouts the wiki cannot serve."""
    subfolders = sorted(
        entry.name
        for entry in docs.iterdir()
        if entry.is_dir() and entry.name not in EXCLUDED_DIRECTORIES
    )
    if subfolders:
        raise WikiBuildError(
            f"docs/ must be flat; move the pages out of: {', '.join(subfolders)}"
        )
    pages = sorted(
        entry
        for entry in docs.iterdir()
        if entry.is_file()
        and entry.suffix == ".md"
        and entry.name not in EXCLUDED_FILES
    )
    seen: dict[str, str] = {}
    for page in pages:
        key = page.stem.casefold()
        if key in seen:
            raise WikiBuildError(
                f"page names differ only in case: {seen[key]}, {page.name}"
            )
        seen[key] = page.name
    return pages


def rewrite_target(
    target: str, page_names: frozenset[str], repository: str, ref: str, source: str
) -> str:
    """Rewrite one link target from its repository form to its wiki form."""
    if target.startswith("#") or SCHEME.match(target):
        return target
    path, separator, anchor = target.partition("#")
    if path.startswith("../"):
        return (
            f"https://github.com/{repository}/blob/{ref}/{path[3:]}{separator}{anchor}"
        )
    if "/" not in path and path.endswith(".md"):
        name = path.removesuffix(".md")
        if name not in page_names:
            raise WikiBuildError(f"{source}: link to a missing page: {target}")
        return f"{name}{separator}{anchor}"
    raise WikiBuildError(
        f"{source}: link must be Page.md, ../path, #anchor, or a URL: {target}"
    )


def convert(
    text: str, page_names: frozenset[str], repository: str, ref: str, source: str
) -> str:
    """Rewrite every link outside fenced code blocks."""

    def replace(match: re.Match[str]) -> str:
        return match.group(1) + rewrite_target(
            match.group(2), page_names, repository, ref, source
        )

    output: list[str] = []
    fence: str | None = None
    for line in text.splitlines(keepends=True):
        opening = FENCE.match(line)
        if fence is not None:
            if opening is not None and opening.group(1) == fence:
                fence = None
            output.append(line)
            continue
        if opening is not None:
            fence = opening.group(1)
            output.append(line)
            continue
        line = REFERENCE_DEFINITION.sub(replace, line)
        output.append(INLINE_LINK.sub(replace, line))
    return "".join(output)


def build(
    docs: pathlib.Path, output: pathlib.Path, repository: str, ref: str
) -> list[str]:
    """Write the wiki pages into `output`, which must be empty or missing."""
    pages = page_files(docs)
    if output.exists() and any(output.iterdir()):
        raise WikiBuildError(f"output directory is not empty: {output}")
    names = frozenset(page.stem for page in pages)
    converted = {
        page.name: convert(
            page.read_text(encoding="utf-8"), names, repository, ref, page.name
        )
        for page in pages
    }
    output.mkdir(parents=True, exist_ok=True)
    for name, text in converted.items():
        (output / name).write_text(text, encoding="utf-8")
    return sorted(converted)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ojd docs build-wiki", description=__doc__)
    parser.add_argument("output", type=pathlib.Path, help="empty output directory")
    parser.add_argument(
        "--repository",
        default=os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPOSITORY),
        help="owner/name for links to files outside docs/",
    )
    parser.add_argument("--ref", default="main", help="branch for those links")
    arguments = parser.parse_args(argv)
    try:
        written = build(DOCS, arguments.output, arguments.repository, arguments.ref)
    except WikiBuildError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Wrote {len(written)} wiki pages to {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
