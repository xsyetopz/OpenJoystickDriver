<!--
Fill each section and delete these comments. Write "None" where a section does not apply.
Back each claim with pasted output, a file, a log excerpt, or a screenshot.
An AI tool may draft sections; you fill Hardware Testing and confirm the rest. Rules: CONTRIBUTING.md#ai-agents.
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

<!-- You fill this from your own Mac and controller, with the output in Verification. Write "None" for a change no controller exercises. -->

- Controller and VID:PID:
- Connection:
- OpenJoystickDriver version (whole About line, see [Finding the Version](https://github.com/xsyetopz/OpenJoystickDriver/blob/main/CONTRIBUTING.md#finding-the-version)):
- macOS version and build (`sw_vers`):
- Input (`ojd controller watch`), rumble (`ojd controller rumble`), lights (`ojd controller light`), virtual gamepad (`ojd virtual show`):
- Every mode and connection, with VID:PID and how to enter it:

## Sources

<!-- Each outside source this change takes facts from (Linux drivers, SDL, other projects, captures, issues, the maker's manual), with the line and the fact. GPL sources give facts only; the code is written independently. -->

## AI Assistance

<!-- Write "None" if no AI tool helped. Otherwise: what it produced, the commands it ran with their output, and each claim you checked by hand with how. -->

## Checklist

- [ ] The base branch is `main`, and this pull request holds one logical change.
- [ ] Generated records and DriverKit files changed only through their generators.
- [ ] Docs, wiki pages, and localization strings match the change.
- [ ] Third-party code comes from an MIT, BSD, zlib, CC0, or Apache-2.0 source, with its notice in `THIRD_PARTY_NOTICES.md`.
- [ ] I read the whole diff and stand behind it. AI help is described above, each commit carries its `Assisted-by:` trailer, and this description ends with the line below.

<!-- Keep the next two lines if an AI tool helped; delete them otherwise. -->

---
Assisted-by: AGENT_NAME:MODEL_VERSION
