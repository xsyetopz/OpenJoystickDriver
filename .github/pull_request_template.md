<!--
Fill each section with exact values. Delete these comments before you submit.
You fill the hardware facts and the "I tested this" statements from your own Mac and controller.
An AI tool can draft the other sections. You read each draft, correct it, and confirm it.
Each claim comes with its proof: pasted command output, a file, a log excerpt, or a screenshot.
Run the command, then write the claim. For a command that cannot run, fill in "Commands you could not run".
-->

## Summary

<!-- Say what changes for a user or a contributor. One logical change in each pull request. An AI tool can draft this section. -->

## Linked Issue

<!-- Write "Closes #123" for the issue that this change fixes. Write "None" if there is no issue. -->

## Evidence

<!-- Add one row for each behavior that this pull request changes. Paste the output below the table, or attach the file. -->
<!-- Example row: | Wireless input decodes | `ojd controller watch 045e:02a9 --duration 10` | output 1 below | Each button changed state | -->

| Behavior | Command that you ran | Output or file | Result |
| --- | --- | --- | --- |
| | | | |

```text
Output 1:

```

## Checks

<!-- Run each check. Tick a box only when the check passed, and paste its output in "Evidence". -->
<!-- If a tool is missing, run `just setup`, then run the check. -->

- [ ] `just verify` passed. Paste the last lines of its output.

## Commands You Could Not Run

<!--
Write "None" if you ran each command above.
For each command that could not run, write all three.
1. The exact step that failed, or the exact item that was missing.
2. The exact error text, or the exact reason. For example, write the Xcode version that you found and the version that the command needs. The file `.swift-version` names the Swift version.
3. What you tried instead, with its output.
-->

## Hardware Testing (you fill this)

<!-- You run this test on your own Mac and fill each line yourself. Paste the output in "Evidence". -->
<!-- Use these commands where they apply: `ojd controller watch <controller> --duration 10`, `ojd controller capture <controller> --duration 10 --json > capture.jsonl`, `ojd controller rumble <controller> --left 255 --right 255 --duration 2`, `ojd controller light <controller> --color FF8000`, `ojd virtual show <controller>`. -->

- Controller name and VID:PID (the two hexadecimal numbers that identify the controller model):
- Connection (USB cable, Bluetooth, or USB receiver):
- OpenJoystickDriver version (the whole line from **About OpenJoystickDriver** of the build that you tested; see [Finding the Version](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/CONTRIBUTING.md#finding-the-version)):
- macOS version and build (`sw_vers`):
- Input, with the output of `ojd controller watch`:
- Rumble, with the output of `ojd controller rumble` and what you felt:
- Lights, with the output of `ojd controller light` and what you saw:
- Virtual gamepad, with the output of `ojd virtual show`:
- Every mode and connection of the controller, from the maker's manual, with the VID:PID of each and how to enter it:

## Sources

<!-- Link each outside source that this change takes facts from: Linux drivers, SDL, other driver projects, Windows or Linux captures, issues, forum threads, the maker's manual. Name the line or section, and the fact taken from it. Facts from GPL sources, such as IDs and byte values, are welcome; the code is written independently. Write "None" if the change uses none. -->

## AI Tool

<!-- Write "None" if you used no AI tool. Rules: CONTRIBUTING.md#ai-agents. An item counts as done when its output is here. -->

- AI tool, version, and model:
- What the AI tool produced (files and sections):
- Commands the AI tool ran, with their output:
- Claims that you checked by hand. For each claim, write the command or the action that you used:

## Checklist

- [ ] The base branch is `main` ([Target Branch](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/CONTRIBUTING.md#target-branch)).
- [ ] This pull request holds one logical change.
- [ ] Each changed behavior has a row in "Evidence" with a command and its output.
- [ ] Generated controller records and generated DriverKit files changed only through their generators.
- [ ] I updated the docs, the wiki pages, and the localization strings that this change affects.
- [ ] I read the whole diff. I stand behind it.
- [ ] If an AI tool helped, I described it in "AI Tool", each commit ends with its `Assisted-by:` trailer, and this description ends with the `Assisted-by:` line below.
- [ ] Any third-party code comes from an MIT, BSD, zlib, CC0, or Apache-2.0 source, with its notice in `THIRD_PARTY_NOTICES.md`.

<!-- If an AI tool wrote this description, keep the next two lines and fill them in. Rules: CONTRIBUTING.md#ai-agents. -->

---
Assisted-by: AGENT_NAME:MODEL_VERSION
