# Structure, hero, badges

## Contents
- What makes people star a project
- Hero block
- Taglines
- Badges
- Section-by-section notes
- Outside the README

## What makes people star a project

Stars are impulse bookmarks. The README earns them when, above the fold, a visitor:

1. Understands what it is from one sentence and one visual.
2. Sees it working (GIF, screenshot, real output).
3. Sees it is cheap to try (one install line, a 3-5 line example).
4. Sees it is alive and trustworthy (passing CI, recent release, real license, real users).
5. Gets a clear angle they can repeat to someone else ("X but zero-config", "the Y for Z").
6. Sees care (tidy hero, consistent formatting), read as a proxy for code quality.

Distribution does the rest: launches cluster stars (Show HN, relevant subreddits, social, newsletters, awesome-lists), and a 24-48 h burst can reach GitHub Trending, which feeds itself. The README's job is to convert that traffic, not create it.

## Hero block

```html
<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" alt="ProjectName" width="280">
  </picture>

  <h3>One-line outcome the user gets.</h3>

  <p>
    <a href="https://github.com/OWNER/REPO/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/OWNER/REPO/ci.yml?branch=main&style=flat-square" alt="CI"></a>
    <a href="https://www.npmjs.com/package/PKG"><img src="https://img.shields.io/npm/v/PKG?style=flat-square" alt="npm version"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/OWNER/REPO?style=flat-square" alt="License"></a>
  </p>

  <p>
    <a href="DOCS_URL">Docs</a> ·
    <a href="DEMO_URL">Demo</a> ·
    <a href="CHANGELOG.md">Changelog</a>
  </p>
</div>

<!-- Demo GIF/screenshot here, ~720px wide -->
```

- No logo? Put the project name as `<h1>` inside the same centered block. Keep the block; consistency across repos matters more than per-repo taste.
- Leave a blank line between HTML blocks and markdown, or GitHub may render the markdown raw.
- Replace every OWNER/REPO/PKG with real values from the repo. Never ship placeholders.

## Taglines

| Pattern | Shape |
|---|---|
| X for Y | "Tailwind for terminal UIs" |
| Outcome + constraint | "Deploy any app in one command. No Dockerfile." |
| Drop-in + number | "A drop-in pip replacement, 10-100x faster" (benchmark linked) |
| Category + difference | "Open-source feature flags you self-host in one binary" |

Rules: under ~12 words; outcome over mechanism; concrete nouns; no "powerful", "modern", "seamless", "next-generation", "blazing".

## Badges

Placement: directly under the tagline, centered, one or two rows. Nowhere else.

Count: 3-7. Choose in this priority:
1. Status: CI, coverage (only if meaningful)
2. Distribution: version, downloads/month
3. Community: Discord/Matrix, contributors
4. License

Rules:
- One style for all (`style=flat-square` or `style=for-the-badge`, not mixed).
- Each badge links to its source (CI to the workflow, version to the registry page).
- A red or "unknown" badge is worse than none. Only add what currently shows green/real data.
- Skip vanity badges: "made with love", "PRs welcome", "awesome", "maintained: yes", language badges GitHub already shows.

Shields.io patterns (verify the endpoint for the ecosystem):
- CI: `https://img.shields.io/github/actions/workflow/status/OWNER/REPO/WORKFLOW.yml?branch=main`
- npm: `https://img.shields.io/npm/v/PKG`, downloads `https://img.shields.io/npm/dm/PKG`
- PyPI: `https://img.shields.io/pypi/v/PKG`, `https://img.shields.io/pypi/pyversions/PKG`
- crates: `https://img.shields.io/crates/v/PKG`
- License: `https://img.shields.io/github/license/OWNER/REPO`
- Discord: `https://img.shields.io/discord/SERVER_ID`

## Section-by-section notes

**Intro (no heading).** Two to four sentences. State the problem in the reader's terms, then the fix, then the difference from the obvious alternative. No "In today's fast-paced world".

**Quickstart.** One package manager shown; others in `<details>`. Then the smallest real example that produces visible output. If setup needs an env var or key, show it.

**Features.** 4-8 bullets. Each names a capability and, where possible, a number or a concrete example. Not every bullet needs a bold lead-in; if you use them, keep the bold to 1-3 words.

**Usage.** The three things people do most, as code. Link to full docs for the rest.

**Comparison.** Only if you can be fair. Include at least one row where an alternative wins; it is the strongest trust signal in the table.

**Roadmap.** A short checklist with real items. Delete it if it would go stale.

**FAQ.** Real questions from issues, in `<details>`. Troubleshooting goes here too.

**Contributing.** "PRs welcome; see CONTRIBUTING.md. Start with issues labeled `good first issue`." That is enough.

**License.** `MIT © Name` with a link to LICENSE.

## Outside the README (tell the user; you usually can't set these)

- About sidebar: one-line description, website, 5-10 topics.
- Social preview image, 1280x640 (Settings > Social preview). It is what shows when the link is shared.
- Releases with real notes; a few `good first issue` labels; Discussions on.
