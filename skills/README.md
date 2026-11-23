# OpenJoystickDriver Agent Skills

These skills follow the [Agent Skills](https://agentskills.io/specification) format and name no particular agent. Copy each skill folder whole into `.agents/skills/` or `.github/skills/` of a project, or `~/.agents/skills/` or `~/.copilot/skills/` for every project.

Claude Code and Codex install the same skills as a plugin, tuned for each agent:

- Claude Code: `/plugin install openjoystickdriver --marketplace xsyetopz/OpenJoystickDriver` (`plugins/claude/openjoystickdriver`)
- Codex: `codex plugin marketplace add xsyetopz/OpenJoystickDriver`, then `codex plugin add openjoystickdriver@openjoystickdriver` (`plugins/codex/openjoystickdriver`)

Each variant holds the same skills, descriptions, and `references` files; `Tests/RepositoryScripts/test_agent_skills.py` checks them and the limits: a description of at most 200 characters and a `SKILL.md` body of at most 200 lines. See [Using Agent Skills](../wiki/Using-Agent-Skills.md).
