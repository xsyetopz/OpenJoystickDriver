# AGENTS.md

- Read `CONTRIBUTING.md` (`#ai-agents`), `LOCALIZATION.md`, `wiki/Home.md`, and `Resources/Schemas/AGENTS.md` first.
- Follow the rules in `.claude/rules/`. Each one gives the pattern, the steps, and a GREEN and a RED example:
  - `evidence-and-checks.md`: base claims and ticks on evidence; build once, test narrow, run `just check` once.
  - `no-unwired-work.md`: a feature is done only when a real session reaches it; write no stubs.
  - `one-format.md`: before `v1.0.0`, keep one format and reject the rest; Swift is canonical.
  - `generated-files.md`: edit the source, then regenerate; never hand-edit generated files.
  - `localization.md`: translate every string in every bundle; an ellipsis marks work in progress.
  - `docs-current.md`: docs describe the code as it is now, and history goes only in `CHANGELOG.md`; preserve SVGs and keep secrets out.

## Duplication

Call `mcp__jscpd__check_duplication` with each function or block before you write it, and reuse the code it finds. Call `mcp__jscpd__get_file_clones` before you refactor a file, and `mcp__jscpd__check_current_directory` after you edit files.
