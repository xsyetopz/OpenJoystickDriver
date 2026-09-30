# Documentation instructions

`docs/` is product documentation for people who use OpenJoystickDriver. Developer and hardware-evidence pages belong in `contributing/`.

- Write for users first. Follow the GitHub Docs style guide and content model, and write prose in ASD-STE100 style.
- Keep the category list in `docs/README.md`. Each category has a `README.md` index with a one-sentence intro and fewer than 10 articles.
- Use one H1 per page, in sentence case. Open with a one-sentence intro. End each article with `## Further reading` when related pages exist.
- Use numbered lists for procedures, with one action per step. Put UI labels in bold.
- Do not hard-wrap Markdown. Write one line per paragraph or list item.
- Do not cite source file paths or line numbers. Ground every claim in source, tests, or recorded hardware evidence. Write "not verified" when evidence is missing.
- Do not add JSON schemas, evidence dumps, generated matrices, or dated agent artifacts under `docs/`. Record hardware observations in the relevant page under `contributing/testing/`.
- `docs/external/` is a gitignored local archive from `./Scripts/ojd docs export-external-issues`. Do not link it from tracked files. Cite the upstream URL instead.
