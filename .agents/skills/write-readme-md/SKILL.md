---
name: write-readme-md
description: Write, rewrite, or review a repository README.md so it converts visitors into users and stars, has the same consistent structure across every repo, and does not read as AI slop. Use whenever the task involves creating or improving a README, a project landing section, badges, a hero/header block, or de-slopping existing docs.
---

# Write README.md

A README is a landing page with one job: in under ten seconds, a stranger should know what this is, see it work, and believe they can try it right now.

Two more jobs:
- **Don't read as machine-written.** Readers pattern-match AI tells (em-dash chains, emoji on every heading, "seamless", "Not just X, it's Y") and discount the whole project. Your defaults lean toward exactly those tells, so the slop pass below is required, not polish.
- **Be consistent.** Every README you write has the same shape. Someone who has read one knows where the install command is in all of them. Do not redesign the structure per repo.

## The fixed structure

Every README uses this skeleton (`assets/README.template.md`), in this order:

1. **Hero** (no heading): centered `<div align="center">` with name or logo, a tagline under ~12 words in `<h3>`, 3-7 badges, optional link row. Demo GIF/screenshot right after.
2. **Intro** (no heading): 2-4 sentences. The problem, the fix, the difference.
3. `## Quickstart`: one install command, then the smallest real example.
4. `## Features`: 4-8 concrete bullets.
5. `## Usage`: common recipes, link to full docs. Long config goes in `<details>` here.
6. `## Comparison`: optional, honest table.
7. `## Roadmap`: optional, only if maintained.
8. `## FAQ`: optional, real questions, in `<details>`.
9. `## Contributing`: 1-3 lines, link to CONTRIBUTING.md.
10. `## License`: one line.

Rules:
- Use these exact heading names. "Getting Started" and "Installation" become `## Quickstart`; "Key Features" becomes `## Features`; "Examples" becomes `## Usage`.
- Don't invent new `##` sections. Extra material goes under `###` inside the closest section or into `<details>`.
- Optional sections are omitted when there's nothing real to put in them. Present sections keep this order.
- Quickstart and License are always present.
- Badges: `?style=flat-square` on all of them, only in the hero, ordered CI, coverage, version, downloads, community, license.
- No emoji in headings or prose.
- Project type changes the content of sections, never their names or order. Voice can follow the project (terse, playful); structure can't.
- If the user asks for a different standard structure, follow it, and offer to edit this section of the skill so future READMEs match.
- When rewriting a README that doesn't follow this structure, conform it and mention the structural changes in your report.

## Workflow

```
- [ ] 1. Investigate the repo (facts before prose)
- [ ] 2. Choose which optional sections apply
- [ ] 3. Write the hero: tagline, badges, demo
- [ ] 4. Write Quickstart, then the rest
- [ ] 5. Slop pass (references/slop-tells.md)
- [ ] 6. Verify every command, link, badge, and number
- [ ] 7. Report what you could not verify
```

### 1. Investigate first

Never write from the repo name alone. Read:
- The package manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`...) for the real name, install target, version, license, entry points.
- The existing README, `/docs`, `/examples`, CLI `--help` output, and the main public API.
- CI config (for the real workflow filename in the badge URL) and the git remote (for `owner/repo`).
- Recent commits or CHANGELOG, to know what is shipped vs planned.

Ask the user only for what the repo can't tell you: audience, the pitch if not obvious, whether a demo asset exists, community links.

### 2-4. Writing

Content by project type:
- **Library**: Quickstart code carries the hero; API snippet beats screenshots.
- **CLI**: terminal GIF (VHS/asciinema) above the fold; real output in Usage.
- **App/UI**: screenshot or GIF first; self-host steps in Quickstart.
- **Framework/infra**: a mermaid diagram in Usage, and a "when not to use this" line in the intro or Comparison.
- **Small utility**: hero, intro, Quickstart, Features, License. 30-80 lines. A short README is not a weak README.

Hero, badge and tagline details: `references/structure.md`. GitHub HTML that works (`align`, `<picture>` dark mode, `<details>`, alerts, mermaid): `references/github-html.md`.

Writing rules:
- Lead with what the reader gets, then how.
- Every speed, size, or scale claim needs a number and a source. No number: drop the claim.
- Quickstart must be copy-paste runnable on a clean machine. No `$` prompts, no output mixed with commands.
- Use the project's real nouns, flags, and function names. No `foo`/`bar`.
- Plain sentences of varied length. Em dashes: 0-2 in the whole README.
- Bullets only for parallel items. Don't bold-lead every bullet.
- No closing summary, no "Happy coding!", no "Built with ❤️".
- Keep it under ~400 lines; move the rest to `/docs`.
- Badges only for data that exists and is passing. No demo asset: leave an HTML comment placeholder and tell the user. Never invent paths or URLs.

### 5. Slop pass

Read `references/slop-tells.md`, then reread the README top to bottom, line by line. For each sentence: does it tell the reader a fact they need? Could it appear unchanged in any other project's README? If so, make it specific or cut it. Check the structure rules above in the same pass.

### 6. Verify

- Run the install and quickstart commands if the environment allows. If not, say so.
- Badge URLs use the real workflow file, package name, and repo slug.
- Relative links and image paths exist.
- The license named matches the LICENSE file.

### 7. Report

Briefly tell the user: what changed, anything you couldn't verify, and any claim you removed for lack of evidence. Don't paste the README back into chat if you wrote it to disk.

## Reviewing an existing README

Read `references/slop-tells.md`, then give findings ordered by impact on a first-time visitor: hero and Quickstart first, structure next, style last. Quote the line, give the fix.

## Files

- `references/structure.md`: hero template, taglines, badges, section notes, what drives stars.
- `references/github-html.md`: HTML GitHub keeps vs strips, dark-mode logos, alerts, mermaid, demo media.
- `references/slop-tells.md`: AI tells with fixes, and what readers don't consider slop.
- `references/examples.md`: before/after rewrites.
- `assets/README.template.md`: the fixed skeleton.
