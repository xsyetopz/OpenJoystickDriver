<!--
Fill every section with exact values. Write "None" or "Not checked" instead of leaving a section vague.
Delete these comments before you submit.
-->

## What This Changes

<!-- What changes for a user or a contributor, in plain words. One logical change per pull request. -->

## Why

<!-- The problem this fixes. Link the issue, for example "Closes #123". -->

## Checks

<!-- Each command you ran and its result. `just check` runs them all. Install a missing tool with `./Scripts/ojd setup` instead of writing "not installed" (CONTRIBUTING.md#ai-agents). -->

## Hardware Testing

<!-- Write "Not tested on hardware" and why, or fill every line. -->

- Controller and VID:PID:
- Connection:
- OpenJoystickDriver version (the whole line from About OpenJoystickDriver of the build you tested; [Finding the Version](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/CONTRIBUTING.md#finding-the-version)):
- macOS version and build (`sw_vers`):
- What I tested and what I saw:

## AI Agent

<!--
Humans: write "None".
AI agents: fill both lines, follow CONTRIBUTING.md#ai-agents, and keep the attribution line your harness adds at the end of this description.
-->

- Agent, model, and harness:
- Human operator who read this pull request and its diff:

## Checklist

- [ ] The base branch is the newest `feat/<version>` branch, not `main` or an earlier `feat/` branch ([Target Branch](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/CONTRIBUTING.md#target-branch)).
- [ ] One logical change.
- [ ] I did not hand-edit generated controller records or generated DriverKit files.
- [ ] I updated the docs, wiki pages, and localization strings this change affects.
- [ ] AI agents only: every commit keeps the harness attribution trailer.
