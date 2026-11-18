# Documentation Instructions

`wiki/` is user documentation and the GitHub wiki source (`just wiki-build OUTDIR`; publish with `just wiki`, `--dry-run` to preview). Developer and hardware-evidence pages go in `docs/`. This file is not published.

- Write for everyday Mac users the way Apple's Mac User Guide does: second person, present tense, active voice, contractions allowed. Use everyday words on task pages and Simplified English (ASD-STE100) on reference pages. Explain a technical word in plain words where a page first uses it. No hard wraps.
- Name UI actions with Apple's verbs: click a button, choose a menu item, select a row or checkbox, turn a switch on or off, press a key or controller button. Write paths as Apple menu > **System Settings** > **Privacy & Security**.
- Flat folder, `Title-Case-With-Hyphens.md`. List every page in `Home.md` and `_Sidebar.md` in the same groups.
- One Title Case H1, a one-sentence intro that says what the page helps the reader do, `## Further Reading` when related pages exist. Task headings start with a verb; troubleshooting headings may start with "If". Pages over ~100 lines get a generated `## Contents`.
- Link as `Page.md#anchor` or a relative path outside `wiki/`. No footnotes, source paths or line numbers.
- Images are app screenshots from `docs/screenshots/`, picked from `just shots-capture` of the current GUI, with alt text that says what the screen shows. Recapture an image when its screen changes.
- Procedures: numbered, one action per step, UI labels in bold.
- Ground claims in source, tests or hardware evidence; otherwise write "not verified". Hardware observations go in `docs/testing/`.
- No schemas, evidence dumps or generated matrices, except the generated blocks of `Error-Codes.md` (`just errors-regenerate --write`) and `Controller-Records.md` (`just vocabulary-regenerate --write`); edit those only via their sources.
