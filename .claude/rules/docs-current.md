---
paths:
  - "**/*"
---

# Docs describe the code as it is now

Comments, the wiki, the README, and the schema descriptions say what the code does today. History belongs only in `CHANGELOG.md`.

- When you change behavior, update every comment and doc that describes it in the same commit.
- Name each behavior, test it, and document it for users where they will look for it: the wiki page or the CLI help.
- Write no "now", "previously", "new", "used to", "renamed from", or "no longer" outside `CHANGELOG.md`.
- Preserve SVG files exactly as they are. Keep secrets out of the repository. Confirm before a destructive write or a publication.

GREEN: `wiki/Wii-Remote.md` says "Pointer X and Pointer Y come from the IR camera while a profile binds them." The `CHANGELOG.md` entry under `[Unreleased]` says the IR pointer was added.

RED: a doc comment says "Previously this used the raw report; now it uses the parsed state." That history goes stale, and it doesn't tell the reader what the function does.
