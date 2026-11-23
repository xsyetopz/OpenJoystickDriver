<!--
Fill each section and delete these comments. Write "None" where a section does not apply.
Back each claim with pasted output, a file, a log excerpt, or a screenshot.
An AI tool may draft sections; you fill Hardware Testing and confirm the rest. Rules: CONTRIBUTING.md#ai-agents.

The maintainer closes the pull request without review when a field says "pending", "untested", "TODO", or "later", when a box is unticked, or when a feature the controller has carries no output from your run.
-->

## Summary

<!-- What changes for a user or a contributor, and why. One logical change per pull request. -->

Closes #

## Changes

<!-- One line per behavior or file group that changed. -->

-

## Verification

<!-- One row per changed behavior, with its output below. Tick `just verify` only after it passed; run `just setup` if a tool is missing. -->

| Behavior | Command | Result |
| --- | --- | --- |
| | | |

```text
<output>
```

- [ ] `just verify` passed (last lines pasted above).

Commands not run: <!-- "None", or for each: the exact failed step, the exact error or reason, and what you tried instead with its output. -->

## Hardware Testing

<!--
You fill this from your own Mac and controller, with the build of this branch. Write "None" for a change no controller exercises.
Answer each feature from the maker's feature list. For each one the controller has, paste the command output and what the controller did. For one it lacks, write "Has none".
-->

- Controller and VID:PID:
- Maker's feature list (link or box photo):
- Connection:
- OpenJoystickDriver version (whole About line, see [Finding the Version](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/CONTRIBUTING.md#finding-the-version)):
- macOS version and build (`sw_vers`):
- Every mode and connection, with VID:PID and how to enter it:

| Feature | Command | Output and What the Controller Did |
| --- | --- | --- |
| Every button, stick, trigger, and D-pad direction, including extra buttons | `ojd controller watch <controller> --duration 30` | |
| Grip vibration, each motor alone | `ojd controller rumble <controller> --left 255`, then `--right 255` | |
| Trigger vibration, each trigger alone | `--left-trigger 255`, then `--right-trigger 255` | |
| Player number lights | `ojd controller player <controller> 1` to `4`, then `off` | |
| Color light | `ojd controller light <controller> --color FF0000`, `00FF00`, `0000FF` | |
| Motion sensor | `ojd controller capture <controller> --json` while still, then tilted | |
| Touchpad | `ojd controller capture <controller> --json` while you drag and press | |
| Speaker or headphone jack | `ojd controller speaker play <controller> <sound file>` | |
| Battery | `ojd controller show <controller>`, beside the maker's app | |
| Virtual gamepad | `ojd virtual show <controller>`, and a game or `just diagnose-browsers` | |

## Sources

<!-- Each outside source this change takes facts from (Linux drivers, SDL, other projects, captures, issues, the maker's manual), with the line and the fact. GPL sources give facts only; the code is written independently. -->

## AI Assistance

<!-- Write "None" if no AI tool helped. Otherwise: what it produced, the commands it ran with their output, and each claim you checked by hand with how. -->

## Checklist

- [ ] The base branch is `main`, and this pull request holds one logical change.
- [ ] Each feature the controller has, in every mode and connection this change touches, has output in Hardware Testing.
- [ ] Generated records and DriverKit files changed only through their generators.
- [ ] Docs, wiki pages, and localization strings match the change.
- [ ] Third-party code comes from an MIT, BSD, zlib, CC0, or Apache-2.0 source, with its notice in `THIRD_PARTY_NOTICES.md`.
- [ ] I read the whole diff and stand behind it. AI help is described above, each commit carries its `Assisted-by:` trailer, and this description ends with the line below.

<!-- Keep the next two lines if an AI tool helped; delete them otherwise. -->

---
Assisted-by: AGENT_NAME:MODEL_VERSION
