# Documentation Instructions

`wiki/` is user documentation and the GitHub wiki source (`just wiki-build OUTDIR`; publish with `just wiki`, `--dry-run` to preview). Developer and hardware-evidence pages go in `docs/`. This file is not published.

- Write for users: GitHub Docs style, ASD-STE100 prose. No hard wraps.
- Flat folder, `Title-Case-With-Hyphens.md`. List every page in `Home.md` and `_Sidebar.md` in the same groups.
- One sentence-case H1, a one-sentence intro, `## Further reading` when related pages exist. Pages over ~100 lines get a generated `## Contents`.
- Link as `Page.md#anchor` or a relative path outside `wiki/`. No footnotes, source paths or line numbers.
- Images are app screenshots from `docs/screenshots/`, picked from `just shots-capture` of the current GUI, with alt text that says what the screen shows. Recapture an image when its screen changes.
- Procedures: numbered, one action per step, UI labels in bold.
- Ground claims in source, tests or hardware evidence; otherwise write "not verified". Hardware observations go in `docs/testing/`.
- No schemas, evidence dumps or generated matrices, except the generated blocks of `Error-Codes.md` (`just errors-regenerate --write`) and `Controller-Records.md` (`just vocabulary-regenerate --write`); edit those only via their sources.
