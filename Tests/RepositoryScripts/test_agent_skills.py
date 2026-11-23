"""Rules for the agent skills in skills/ and the Claude and Codex plugins under plugins/.

Each variant holds the same skills. A skill follows the Agent Skills specification (agentskills.io)
and Anthropic's authoring rules, within this project's limits: a description of at most 200
characters and a SKILL.md body of at most 200 lines. Reference files are identical across variants,
so a fact changes in one place per file. Plugin manifests carry the app version.
"""

from __future__ import annotations

import json
import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLAUDE_PLUGIN = ROOT / "plugins" / "claude" / "openjoystickdriver"
CODEX_PLUGIN = ROOT / "plugins" / "codex" / "openjoystickdriver"
VARIANTS = {
    "standalone": ROOT / "skills",
    "claude": CLAUDE_PLUGIN / "skills",
    "codex": CODEX_PLUGIN / "skills",
}
# Standalone skills keep to the keys every Agent Skills client reads. Claude Code adds argument and
# tool hints. Codex reads only name and description; its interface lives in agents/openai.yaml.
ALLOWED_KEYS = {
    "standalone": {"name", "description", "license", "compatibility", "metadata"},
    "claude": {
        "name",
        "description",
        "license",
        "compatibility",
        "metadata",
        "argument-hint",
        "allowed-tools",
    },
    "codex": {"name", "description"},
}
# Tokens that bind a skill to one agent; a standalone skill names none of them.
TOOL_TOKENS = ("$ARGUMENTS", "/openjoystickdriver:", "Claude", "Codex", "allowed-tools")
NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
LINK = re.compile(r"\]\(([^)#]+)\)")
MAX_DESCRIPTION = 200
MAX_BODY_LINES = 200
MAX_REFERENCE_LINES_WITHOUT_CONTENTS = 100


def split_skill(path: Path) -> tuple[dict[str, str], list[str]]:
    """Returns the top-level frontmatter scalars and the body lines of a SKILL.md."""
    lines = path.read_text().splitlines()
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        raise AssertionError(f"{path}: frontmatter must open and close with ---")
    end = lines.index("---", 1)
    fields: dict[str, str] = {}
    for line in lines[1:end]:
        if not line or line.startswith(" "):
            continue
        key, _, value = line.partition(":")
        fields[key] = value.strip().strip('"')
    return fields, lines[end + 1 :]


def skill_dirs(variant: str) -> dict[str, Path]:
    return {
        path.parent.name: path.parent for path in VARIANTS[variant].glob("*/SKILL.md")
    }


def app_version() -> str:
    info = ROOT / "Sources" / "OpenJoystickDriver" / "App" / "Info.plist"
    return str(plistlib.loads(info.read_bytes())["CFBundleShortVersionString"])


class AgentSkillTests(unittest.TestCase):
    def test_every_variant_holds_the_same_skills(self) -> None:
        names = {variant: set(skill_dirs(variant)) for variant in VARIANTS}
        self.assertTrue(names["standalone"], "skills/ holds no skill")
        for variant, found in names.items():
            self.assertEqual(found, names["standalone"], variant)

    def test_frontmatter_follows_the_specification(self) -> None:
        for variant in VARIANTS:
            for name, directory in skill_dirs(variant).items():
                with self.subTest(variant=variant, skill=name):
                    fields, _ = split_skill(directory / "SKILL.md")
                    self.assertLessEqual(set(fields), ALLOWED_KEYS[variant])
                    self.assertEqual(fields.get("name"), name)
                    self.assertRegex(name, NAME)
                    self.assertLessEqual(len(name), 64)
                    self.assertNotRegex(name, "claude|anthropic")
                    description = fields.get("description", "")
                    self.assertTrue(description)
                    self.assertLessEqual(len(description), MAX_DESCRIPTION)
                    self.assertNotRegex(description, "[<>]")
                    self.assertIn("Use when", description)

    def test_descriptions_match_across_variants(self) -> None:
        for name, directory in skill_dirs("standalone").items():
            expected = split_skill(directory / "SKILL.md")[0]["description"]
            for variant in ("claude", "codex"):
                with self.subTest(variant=variant, skill=name):
                    fields, _ = split_skill(skill_dirs(variant)[name] / "SKILL.md")
                    self.assertEqual(fields["description"], expected)

    def test_bodies_stay_short_and_links_resolve(self) -> None:
        for variant in VARIANTS:
            for name, directory in skill_dirs(variant).items():
                with self.subTest(variant=variant, skill=name):
                    _, body = split_skill(directory / "SKILL.md")
                    self.assertLessEqual(len(body), MAX_BODY_LINES)
                    for target in LINK.findall("\n".join(body)):
                        self.assertTrue((directory / target).is_file(), target)

    def test_standalone_skills_name_no_agent(self) -> None:
        for name, directory in skill_dirs("standalone").items():
            text = (directory / "SKILL.md").read_text()
            for token in TOOL_TOKENS:
                with self.subTest(skill=name, token=token):
                    self.assertNotIn(token, text)

    def test_references_match_across_variants(self) -> None:
        for name, directory in skill_dirs("standalone").items():
            references = {
                path.relative_to(directory): path.read_bytes()
                for path in directory.glob("references/*")
            }
            for variant in ("claude", "codex"):
                other = skill_dirs(variant)[name]
                found = {
                    path.relative_to(other): path.read_bytes()
                    for path in other.glob("references/*")
                }
                with self.subTest(variant=variant, skill=name):
                    self.assertEqual(found, references)
            for path, data in references.items():
                with self.subTest(skill=name, reference=str(path)):
                    lines = data.decode().splitlines()
                    if len(lines) > MAX_REFERENCE_LINES_WITHOUT_CONTENTS:
                        self.assertIn("## Contents", lines)

    def test_codex_skills_declare_their_interface(self) -> None:
        for name, directory in skill_dirs("codex").items():
            with self.subTest(skill=name):
                text = (directory / "agents" / "openai.yaml").read_text()
                for key in ("display_name:", "short_description:", "default_prompt:"):
                    self.assertIn(key, text)

    def test_plugin_manifests_carry_the_app_version(self) -> None:
        for manifest in (
            CLAUDE_PLUGIN / ".claude-plugin" / "plugin.json",
            CODEX_PLUGIN / "plugin.json",
        ):
            with self.subTest(manifest=str(manifest.relative_to(ROOT))):
                document = json.loads(manifest.read_text())
                self.assertEqual(document["name"], "openjoystickdriver")
                self.assertEqual(document["version"], app_version())

    def test_marketplaces_point_at_the_plugins(self) -> None:
        claude = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text())
        codex = json.loads(
            (ROOT / ".agents" / "plugins" / "marketplace.json").read_text()
        )
        self.assertEqual(
            [(ROOT / entry["source"]).resolve() for entry in claude["plugins"]],
            [CLAUDE_PLUGIN],
        )
        self.assertEqual(
            [(ROOT / entry["source"]["path"]).resolve() for entry in codex["plugins"]],
            [CODEX_PLUGIN],
        )


if __name__ == "__main__":
    unittest.main()
