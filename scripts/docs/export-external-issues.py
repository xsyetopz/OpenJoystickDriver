#!/usr/bin/env python3
"""Export GitHub issues referenced by OpenJoystickDriver design work."""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs" / "external"
OJD_REPO = "xsyetopz/OpenJoystickDriver"
SDL_REPO = "libsdl-org/SDL"
ISSUE_FIELDS = (
    "number,title,state,labels,author,createdAt,updatedAt,closedAt,url,body,comments"
)
PR_FIELDS = (
    "number,title,state,isDraft,author,createdAt,updatedAt,closedAt,mergedAt,"
    "url,body,comments,files,commits,reviews"
)


class ExportError(RuntimeError):
    pass


def sanitize_external_text(text: str) -> str:
    text = re.sub(
        r"(https://private-user-images\.githubusercontent\.com/[^?\s\"<>]+)\?[^\s\"<>]+",
        r"\1",
        text,
    )
    return re.sub(
        r"(https://github\.com/[^?\s\"<>]+)\?[^#\s\"<>]*(#[^\s\"<>]+)?",
        lambda match: match.group(1) + (match.group(2) or ""),
        text,
    )


def gh_json(args: list[str]) -> Any:
    command = ["gh", *args]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ExportError(f"{' '.join(command)} failed: {detail}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ExportError(f"{' '.join(command)} returned invalid JSON") from error


def login(author: Any) -> str:
    return (
        str(author.get("login") or "(unknown)")
        if isinstance(author, dict)
        else "(unknown)"
    )


def value(item: Any) -> str:
    return "—" if item is None or item == "" else str(item)


def body(item: Any) -> str:
    text = sanitize_external_text(str(item or "").strip())
    return text or "_No description provided._"


def comments(items: Any) -> str:
    if not isinstance(items, list) or not items:
        return "_No comments._\n"
    blocks = []
    for item in items:
        blocks.append(
            f"### {login(item.get('author'))} — {value(item.get('createdAt'))}\n\n"
            f"[Source comment]({value(item.get('url'))})\n\n"
            f"{body(item.get('body'))}\n"
        )
    return "\n".join(blocks)


def render_issue(repo: str, issue: dict[str, Any]) -> str:
    labels = ", ".join(
        str(item.get("name"))
        for item in issue.get("labels") or []
        if isinstance(item, dict) and item.get("name")
    )
    return (
        f"# #{issue['number']}: {issue['title']}\n\n"
        "> External GitHub snapshot. GitHub is authoritative if this file is stale.\n\n"
        f"- **Repository:** `{repo}`\n"
        f"- **Source:** {issue['url']}\n"
        f"- **State:** {issue['state']}\n"
        f"- **Author:** {login(issue.get('author'))}\n"
        f"- **Created:** {value(issue.get('createdAt'))}\n"
        f"- **Updated:** {value(issue.get('updatedAt'))}\n"
        f"- **Closed:** {value(issue.get('closedAt'))}\n"
        f"- **Labels:** {labels or '—'}\n\n"
        f"## Report\n\n{body(issue.get('body'))}\n\n"
        f"## Comments\n\n{comments(issue.get('comments'))}"
    )


def render_pull(repo: str, pull: dict[str, Any]) -> str:
    file_lines = [
        f"- `{item.get('path')}` (+{item.get('additions', 0)}/-{item.get('deletions', 0)}, "
        f"{item.get('changeType', 'UNKNOWN')})"
        for item in pull.get("files") or []
    ]
    commit_lines = [
        f"- `{str(item.get('oid', ''))[:12]}` {item.get('messageHeadline', '')}"
        for item in pull.get("commits") or []
    ]
    review_blocks = []
    for item in pull.get("reviews") or []:
        review_blocks.append(
            f"### {login(item.get('author'))} — {item.get('state', 'UNKNOWN')}\n\n"
            f"Submitted: {value(item.get('submittedAt'))}\n\n"
            f"{body(item.get('body'))}\n"
        )
    return (
        f"# PR #{pull['number']}: {pull['title']}\n\n"
        "> External GitHub snapshot. GitHub is authoritative if this file is stale.\n\n"
        f"- **Repository:** `{repo}`\n"
        f"- **Source:** {pull['url']}\n"
        f"- **State:** {pull['state']}\n"
        f"- **Draft:** {pull.get('isDraft', False)}\n"
        f"- **Author:** {login(pull.get('author'))}\n"
        f"- **Created:** {value(pull.get('createdAt'))}\n"
        f"- **Updated:** {value(pull.get('updatedAt'))}\n"
        f"- **Closed:** {value(pull.get('closedAt'))}\n"
        f"- **Merged:** {value(pull.get('mergedAt'))}\n\n"
        f"## Description\n\n{body(pull.get('body'))}\n\n"
        f"## Files\n\n{chr(10).join(file_lines) or '_No files reported._'}\n\n"
        f"## Commits\n\n{chr(10).join(commit_lines) or '_No commits reported._'}\n\n"
        f"## Conversation\n\n{comments(pull.get('comments'))}\n"
        f"## Reviews\n\n{chr(10).join(review_blocks) or '_No reviews._'}\n"
    )


def write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n")


def export_ojd() -> None:
    summaries = gh_json(
        [
            "issue",
            "list",
            "--repo",
            OJD_REPO,
            "--state",
            "all",
            "--limit",
            "200",
            "--json",
            "number",
        ]
    )
    issues = [
        gh_json(
            ["issue", "view", str(number), "--repo", OJD_REPO, "--json", ISSUE_FIELDS]
        )
        for number in sorted(int(item["number"]) for item in summaries)
    ]
    destination = DOCS / "OpenJoystickDriver"
    for issue in issues:
        write(
            destination / f"issue-{issue['number']}.md", render_issue(OJD_REPO, issue)
        )
    rows = [
        f"| [#{issue['number']}](issue-{issue['number']}.md) | {issue['state']} | "
        f"{str(issue['title']).replace('|', '&#124;')} |"
        for issue in issues
    ]
    write(
        destination / "README.md",
        "# OpenJoystickDriver GitHub Issues\n\n"
        "Snapshot of every issue returned by the GitHub CLI for "
        f"[{OJD_REPO}](https://github.com/{OJD_REPO}/issues). GitHub remains the source of truth. "
        "Expiring authentication query parameters are stripped from quoted links.\n\n"
        "Refresh from the repository root:\n\n"
        "```bash\n./scripts/ojd docs export-external-issues\n```\n\n"
        "| Issue | State | Title |\n| --- | --- | --- |\n" + "\n".join(rows),
    )


def export_sdl() -> None:
    issues = [
        gh_json(
            ["issue", "view", str(number), "--repo", SDL_REPO, "--json", ISSUE_FIELDS]
        )
        for number in (15_790, 15_663)
    ]
    pulls = [
        gh_json(["pr", "view", str(number), "--repo", SDL_REPO, "--json", PR_FIELDS])
        for number in (15_183,)
    ]
    destination = DOCS / "sdl"
    for issue in issues:
        write(
            destination / f"issue-{issue['number']}.md", render_issue(SDL_REPO, issue)
        )
    for pull in pulls:
        write(destination / f"pull-{pull['number']}.md", render_pull(SDL_REPO, pull))
    rows = [
        f"| Issue | [#{item['number']}](issue-{item['number']}.md) | {item['state']} | "
        f"{str(item['title']).replace('|', '&#124;')} |"
        for item in issues
    ] + [
        f"| Pull request | [#{item['number']}](pull-{item['number']}.md) | {item['state']} | "
        f"{str(item['title']).replace('|', '&#124;')} |"
        for item in pulls
    ]
    write(
        destination / "README.md",
        "# SDL GitHub References\n\n"
        "Snapshots of the SDL issues and pull request referenced by OJD compatibility work. "
        "GitHub remains the source of truth. Expiring authentication query parameters are stripped "
        "from quoted links.\n\n"
        "Refresh from the repository root:\n\n"
        "```bash\n./scripts/ojd docs export-external-issues\n```\n\n"
        "| Kind | Reference | State | Title |\n| --- | --- | --- | --- |\n"
        + "\n".join(rows),
    )


def main() -> int:
    try:
        export_ojd()
        export_sdl()
    except (ExportError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("Exported OpenJoystickDriver issues to docs/external/OpenJoystickDriver")
    print("Exported SDL references to docs/external/sdl")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
