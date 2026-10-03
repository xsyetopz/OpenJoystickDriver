# Documentation instructions

`docs/` is product documentation for people who use OpenJoystickDriver. Developer and hardware-evidence pages belong in `contributing/`.

`docs/` is also the source of the GitHub wiki. `./Scripts/ojd docs build-wiki OUTDIR` converts it, and the `wiki` workflow publishes it after each push to `main`. This file is not published.

- Write for users first. Follow the GitHub Docs style guide and content model, and write prose in ASD-STE100 style.
- Keep every page flat in `docs/`, with no subfolders. Name each page in Title-Case-With-Hyphens, for example `Known-Issues.md`, because the wiki uses the file name as the page name.
- List every page in `Home.md` and `_Sidebar.md`, in the same groups.
- Use one H1 per page, in sentence case. Open with a one-sentence intro. End each page with `## Further reading` when related pages exist.
- Give a page longer than about 100 lines a `## Contents` heading after the intro, and fill it with a TOC generator. Update the list after each heading change.
- Link to another page as `Page.md` or `Page.md#anchor`. Link to a file outside `docs/` with a relative path, for example `../contributing/README.md`. The wiki build rewrites both forms.
- Do not use footnotes or images, because the wiki does not render them from this folder.
- Use numbered lists for procedures, with one action per step. Put UI labels in bold.
- Do not hard-wrap Markdown. Write one line per paragraph or list item.
- Do not cite source file paths or line numbers. Ground every claim in source, tests, or recorded hardware evidence. Write "not verified" when evidence is missing.
- Do not add JSON schemas, evidence dumps, generated matrices, or dated agent artifacts under `docs/`. Record hardware observations in the relevant page under `contributing/testing/`.
- `docs/external/` is a gitignored local archive from `./Scripts/ojd docs export-external-issues`. Do not link it from tracked files. Cite the upstream URL instead. The wiki build skips it.
