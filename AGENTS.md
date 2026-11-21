# AGENTS.md

- Read `CONTRIBUTING.md` (`#ai-agents`), `LOCALIZATION.md`, `wiki/Home.md`, and `Resources/Schemas/AGENTS.md` first.
- Before you write a function or block, call `mcp__jscpd__check_duplication` and reuse what it finds. Call `mcp__jscpd__get_file_clones` before you refactor a file, and `mcp__jscpd__check_current_directory` after you edit.
- Write button, menu and disclosure titles in Title Case where the language has it, and end one with `...` only where macOS does or for work in progress, per Apple's HIG and `LOCALIZATION.md`.
- Give each control a localized `.help` tooltip per the HIG (sentence case, starts with a verb, at most 75 characters) and an accessible name that contains its visible title, to meet the HIG and EN 301 549 clause 11 (WCAG 2.2 AA) together.
- Ask the user before you pass `--force` past an `ojd` confirmation or grant endpoint access, and revoke each grant you made when its run ends.

- Run each task through `just`. `just` lists the recipes. Check each change with the narrowest one, such as `just swift::test` or `just lint`, and run `just verify` once before you finish a change that alters behavior.
- Fix the cause of each lint, type, or guard error in the code, and keep the shared lint and format configs as they are.
- Put project recipes in `project.just`. A recipe there named `project-<task>`, such as `project-verify` or `project-test`, runs after the languages' `<task>` in `.just/`, so a project extends `just verify` there.
- Write commit messages as Conventional Commits; the commit-msg hook checks them.
- Attribute your work with the tag `Assisted-by: AGENT_NAME:MODEL_VERSION`, such as `Assisted-by: Claude Code:claude-opus-5-5`, wherever you write. A commit message ends with it as a trailer, and the operator stays the author. A pull request body, issue comment, or review ends with a `---` line, then the tag; an edit of an existing post keeps or adds it. An issue form holds `AGENT_NAME:MODEL_VERSION` in its **Assisted-by** field. Check the body for the tag before you post it.
- Commit each finished slice of work as soon as its narrowest check passes: one concern per commit, such as one doc page, one batch of strings, or one fix with its test, so `git revert` undoes it alone and `git diff` shows only the slice in progress. Stage paths by name with `git add <path>`, never `git add -A`, so another task's files stay out. Commit locally only; push or publish after the user confirms.
- When a recipe reports a missing tool, run `just setup`, which installs the pinned ones. Install any it can't, such as `just`, swiftly, or Xcode, with the system's package manager, then rerun the recipe. Tell the user what you installed, and keep the check instead of skipping it.
- Write tests with Swift Testing: `import Testing`, `@Test`, `#expect`, and `#require`. XCTest is only for `*UITests` targets, which need `XCUIApplication`; `just guard` reports XCTest anywhere else.
- Keep the settings loop at the end of `Package.swift`. It turns on Swift 6 mode, the upcoming features, strict memory safety, and warnings as errors for each target, and `just guard` checks that each target keeps them.
- Mark an unsafe expression with `unsafe`, and spell an existential `any P`.
- Build an app in Xcode against `Config/Base.xcconfig`, which sets the same flags as the package.
- Build Swift through `just`, which selects one toolchain and SDK for the checkout through `Scripts/with-env.sh`. When worktrees fill the disk, `just swift::clean-worktrees` deletes each `.build` folder no process is using.
- Document each `public` or `open` declaration other modules can reach. Internal and private code needs no docs, and SwiftLint reports a `public` member of an internal type instead.
