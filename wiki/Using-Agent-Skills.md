# Using Agent Skills

Install the OpenJoystickDriver (OJD) skills so an AI coding agent can diagnose a controller, write a patch or record, add rumble, generate documents, and package a mod with the `ojd` command.

## The Skills

Each skill does one job. The agent loads a skill when your request matches its description.

| Skill | Use it when |
| --- | --- |
| `diagnosing-ojd-controllers` | a controller is missing, misread, or silent, or you need a support report |
| `writing-ojd-controller-patches` | OJD knows the model but one detail is wrong |
| `writing-ojd-controller-records` | OJD doesn't know the controller |
| `adding-ojd-rumble` | the controller's motors stay still |
| `generating-ojd-documents` | several models differ by a few details |
| `packaging-ojd-mods` | you want to share your files with other users |

The skills run `ojd` commands on your Mac. The agent asks you before it passes `--force`, and asks you to press controls while it captures.

## Install the Claude Code Plugin

1. In Claude Code, run `/plugin install openjoystickdriver --marketplace xsyetopz/OpenJoystickDriver`.
2. Call a skill by name, such as `/openjoystickdriver:adding-ojd-rumble 0079:0006`, or describe the task.

## Install the Codex Plugin

1. In Terminal, run `codex plugin marketplace add xsyetopz/OpenJoystickDriver`.
2. Run `codex plugin add openjoystickdriver@openjoystickdriver`.
3. Start Codex and describe the task, such as "add rumble to my 0079:0006 pad".

## Install the Skills in Another Agent

The `skills` folder of the repository holds the same skills in a form any agent that reads Agent Skills can use, such as GitHub Copilot. Copy each skill folder into one of these folders:

| Folder | Scope |
| --- | --- |
| `.agents/skills/` in your project | one project, for agents that read the shared folder |
| `.github/skills/` in your project | one project, for GitHub Copilot |
| `~/.agents/skills/` | every project |
| `~/.copilot/skills/` | every project, for GitHub Copilot |

Keep each folder whole: a skill reads the files in its `references` folder.

## Further Reading

- [Support Ladder](Support-Ladder.md)
- [Controller Records](Controller-Records.md)
- [Writing Controller Mods](Writing-Controller-Mods.md)
- [Command Reference](Command-Reference.md)
