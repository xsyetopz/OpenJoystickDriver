# AGENTS.md

- Read `CONTRIBUTING.md` (`#ai-agents`), `LOCALIZATION.md`, `wiki/Home.md`, and `Resources/Schemas/AGENTS.md` first.
- Before you write a function or block, call `mcp__jscpd__check_duplication` and reuse what it finds. Call `mcp__jscpd__get_file_clones` before you refactor a file, and `mcp__jscpd__check_current_directory` after you edit.
- Write button, menu and disclosure titles in Title Case where the language has it, and end one with `...` only where macOS does or for work in progress, per Apple's HIG and `LOCALIZATION.md`.
- Ask the user before you pass `--force` past an `ojd` confirmation or grant endpoint access, and revoke each grant you made when its run ends.

<!-- bedrock -->
- Run each task through `just`. `just` lists the recipes. Check each change with the narrowest one, such as `just rust::test` or `just lint`, and run `just verify` once before you finish a change that alters behavior.
- Fix the cause of each lint, type, or guard error in the code. Keep the shared configs as they are; the bedrock that wrote them owns them.
- Put project recipes in `project.just`. The `justfile` and `.just/` are shared and get replaced on the next adopt. A recipe there named `project-<task>`, such as `project-verify` or `project-test`, runs after the languages' `<task>`, so a project extends `just verify` there. `project-pre-typecheck` runs before the TypeScript type check, for a build the types import.
- Write commit messages as Conventional Commits; the commit-msg hook checks them.
- When a recipe reports a missing tool, run `just setup`, which installs the pinned ones. Install any it can't, such as `just`, Bun, rustup, or Xcode, with the system's package manager, then rerun the recipe. Tell the user what you installed, and keep the check instead of skipping it.
<!-- /bedrock -->

<!-- swift-bedrock -->
- Write tests with Swift Testing: `import Testing`, `@Test`, `#expect`, and `#require`. XCTest is only for `*UITests` targets, which need `XCUIApplication`; `just lint-fix` converts other XCTest files.
- Keep the `// >>> swift-bedrock` block at the end of `Package.swift`. It turns on Swift 6 mode, the upcoming features, strict memory safety, and warnings as errors for each target.
- Mark an unsafe expression with `unsafe`, and spell an existential `any P`.
- Build an app in Xcode against `Config/Bedrock.xcconfig`, which sets the same flags as the package.
- Build Swift through `just`, which turns on the compile cache every checkout shares, in a repository without C or C++. When worktrees fill the disk, `just swift::clean-worktrees` deletes each `.build` folder no process is using.
- Document each `public` or `open` declaration other modules can reach. Internal and private code needs no docs, and SwiftLint reports a `public` member of an internal type instead.
<!-- /swift-bedrock -->
