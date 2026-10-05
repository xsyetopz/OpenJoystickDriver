"""Publish `wiki/` to the GitHub wiki repository."""

from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

from Scripts.Documentation.wiki import build as wiki_build

ORIGIN_PATTERN = re.compile(
    r"^(?P<prefix>.*github\.com[:/])(?P<repository>[^/]+/[^/]+?)(?:\.git)?/?$"
)


class PublishError(RuntimeError):
    pass


def git(
    *arguments: str, cwd: pathlib.Path | None = None, check: bool = True
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["git", *arguments], cwd=cwd, capture_output=True, text=True, check=False
    )
    if check and result.returncode != 0:
        raise PublishError(f"git {arguments[0]} failed: {result.stderr.strip()}")
    return result


def origin_wiki(root: pathlib.Path) -> tuple[str, str]:
    """Return (wiki remote URL, owner/name) derived from the origin remote."""
    result = git("remote", "get-url", "origin", cwd=root, check=False)
    match = ORIGIN_PATTERN.match(result.stdout.strip())
    if result.returncode != 0 or match is None:
        repository = wiki_build.DEFAULT_REPOSITORY
        return f"https://github.com/{repository}.wiki.git", repository
    repository = match["repository"]
    return f"{match['prefix']}{repository}.wiki.git", repository


def source_label(root: pathlib.Path) -> str:
    """Name the source commit, marked -dirty when wiki/ has uncommitted changes."""
    commit = git("rev-parse", "HEAD", cwd=root).stdout.strip()
    status = git("status", "--porcelain", "--", "wiki", cwd=root).stdout.strip()
    return f"{commit}-dirty" if status else commit


def publish(
    root: pathlib.Path,
    remote: str,
    repository: str,
    label: str,
    ref: str,
    dry_run: bool,
) -> str:
    """Return a status line; raise PublishError when the wiki cannot be updated."""
    with tempfile.TemporaryDirectory(prefix="ojd-wiki-") as scratch:
        pages = pathlib.Path(scratch) / "pages"
        checkout = pathlib.Path(scratch) / "checkout"
        wiki_build.build(root / "wiki", pages, repository, ref)
        cloned = git("clone", "-q", "--depth", "1", remote, str(checkout), check=False)
        if cloned.returncode != 0:
            raise PublishError(
                f"cannot clone the wiki repository {redact(remote)}.\n"
                f"{redact(cloned.stderr.strip())}\n"
                "GitHub creates it with the first page. Create that page at "
                f"https://github.com/{repository}/wiki and run this again."
            )
        for entry in checkout.iterdir():
            if entry.name != ".git":
                shutil.rmtree(entry) if entry.is_dir() else entry.unlink()
        for page in pages.iterdir():
            shutil.copy2(page, checkout / page.name)
        git("add", "-A", cwd=checkout)
        if (
            git("diff", "--cached", "--quiet", cwd=checkout, check=False).returncode
            == 0
        ):
            return "The wiki is current."
        stat = git("diff", "--cached", "--stat", cwd=checkout).stdout.rstrip()
        if dry_run:
            return f"{stat}\nDry run: nothing was committed or pushed."
        git("commit", "-q", "-m", f"Sync wiki from {label}", cwd=checkout)
        git("push", "-q", "origin", "HEAD", cwd=checkout)
        return f"{stat}\nPublished the wiki from {label}."


def redact(text: str) -> str:
    """Hide credentials embedded in a URL."""
    return re.sub(r"://[^/@\s]+@", "://***@", text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ojd docs publish-wiki", description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="show the diff stat without pushing"
    )
    parser.add_argument(
        "--remote", help="wiki repository URL (default: derived from origin)"
    )
    parser.add_argument(
        "--source", help="source label for the commit message (default: git HEAD)"
    )
    parser.add_argument("--ref", default="main", help="branch for repository links")
    arguments = parser.parse_args(argv)
    root = wiki_build.ROOT
    try:
        derived, repository = origin_wiki(root)
        message = publish(
            root,
            arguments.remote or derived,
            repository,
            arguments.source or source_label(root),
            arguments.ref,
            arguments.dry_run,
        )
    except (PublishError, wiki_build.WikiBuildError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
