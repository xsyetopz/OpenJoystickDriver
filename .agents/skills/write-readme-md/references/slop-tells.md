# Slop tells, and what is not slop

## Contents
- How readers judge
- Prose tells (with fixes)
- Structure and formatting tells
- Content tells (the worst kind)
- What readers do NOT call slop
- Final read-through questions

## How readers judge

Developers skim a README in seconds. They are not running a detector; they are pattern-matching. A few tells make them reread every claim with suspicion, and the project inherits that suspicion. Common reactions in public threads: a README full of em dashes, emoji, "feature squares" and ASCII diagrams that the author's pre-AI projects never had; emoji sprinkled through READMEs and log lines; an LLM README with em dashes swapped for double hyphens (readers still notice).

No single tell proves AI authorship (models learned these habits from human writing), and good writers use em dashes. The problem is density and emptiness: many tells together, wrapped around little information. Wikipedia's "Signs of AI writing" field guide frames it the same way: signs point to weaknesses (puffery, editorializing, section-ending summaries), not proof.

So the goal is not "evade detection". It is: remove the habits that carry no information, and replace them with facts.

## Prose tells

| Tell | Example | Fix |
|---|---|---|
| Em-dash chains | "Fast — really fast — and simple" | Commas, periods, parentheses. Aim for 0-2 per README. Double hyphens `--` are the same tell. |
| "Not X, it's Y" / "not just X, but Y" | "It's not just a CLI, it's a workflow" | Say what it is. "A CLI that runs your release steps." |
| Hype adjectives | powerful, robust, seamless, intuitive, cutting-edge, state-of-the-art, next-gen, blazing fast, enterprise-grade, production-ready | Replace with the number or fact behind the adjective, or delete. |
| Slop verbs | leverage, empower, elevate, unlock, streamline, supercharge, revolutionize, harness the power of, delve | Plain verbs: use, let, speed up, run, read. |
| Reader-flattering openers | "Whether you're a beginner or a seasoned pro..." / "In today's fast-paced world" / "Look no further" | Start with what the tool does. |
| Signposting | "Here's why:", "Let's dive in", "It's worth noting that", "At its core" | Delete the signpost; keep the content. |
| Forced triplets | "fast, flexible, and fun" / three-item lists everywhere | Use the number of items you actually have. Two is fine. |
| Hedge stacks | "can potentially help to improve" | "improves" (if true) or cut. |
| Inflated importance | "a testament to", "plays a crucial role", "ever-evolving landscape" | Cut. |
| Closing summary | "In summary, X is a powerful tool that..." | Delete. READMEs do not need conclusions. |
| Sign-offs | "Happy coding!", "Built with ❤️", "Made with love by" | Delete. |
| "Designed to" | "X is designed to make Y easy" | "X does Y." Claim the behavior, not the intent. |

## Structure and formatting tells

- **Emoji on every heading** (🚀 Getting Started, ✨ Features, 🛠️ Installation, 🤝 Contributing, 📄 License). Emoji used by reflex, especially 🚀 ✨ 🔥 💡 🎯 ⚡ 🌟. Fix: none by default; if the project voice wants them, one per heading max, chosen to mean something, never in prose.
- **Emoji-led feature bullets where the emoji is decoration**: "🔥 **Blazing Fast**: Experience lightning speed".
- **Bold lead-in on every bullet**, each followed by a colon and a restatement. "**Easy Setup**: Setting up is easy." Fix: plain bullets that state a fact.
- **Feature grid / "feature squares"** of 9-12 boxes with generic labels. Fix: 4-8 bullets with specifics.
- **Full directory tree** of the repo dumped into the README. Fix: omit, or show only the 3-6 paths a contributor needs.
- **Symmetrical sections** every one the same length, each ending with a summary line.
- **Template residue**: `your-username`, `your_api_key_here` left unexplained, TODO, Lorem ipsum, "Add screenshots here", sections with one generic line.
- **Over-sectioned small project**: 15 headings for a 200-line script. Fix: 3-5 sections.
- **Boilerplate Contributing**: the fork/branch/commit/push/PR five-step list. Fix: one line and a link.
- **ASCII architecture diagrams that are wrong or decorative**. Fix: a correct mermaid diagram, or none.
- **Badge wall**: 10+ badges, mixed styles, some broken.
- **Hashtag-ish or keyword stuffing** in headings.

## Content tells (the worst kind)

These are the ones that destroy trust because they are false, not just stylistic:

- Benchmarks or speed claims with no numbers or no source.
- Features listed that the code does not have (often "planned" items written in present tense).
- Install commands for package registries the project is not published to.
- Badges pointing at nonexistent workflows or packages.
- Invented links (docs site, Discord) or image paths that 404.
- API examples using functions or flags that do not exist.
- Generic examples (`foo`, `bar`, `example.com`) where a real use case would show value.

Fix: everything stated must be checked against the repo or removed. Write "planned" items in the Roadmap, nowhere else.

## What readers do NOT call slop

People are fine with AI-assisted docs that read as edited and true. Public discussion makes the split clear: technical documentation is where AI help is accepted; marketing voice is where readers bristle. Some developers now hand-write the human-facing README for the sake of connection while letting agents handle internal docs. What reads as human:

- **Specifics.** Real numbers, real flags, real error messages, real file names. Nothing generic survives contact with a real codebase.
- **A point of view.** "We built this because X kept timing out on large monorepos." An origin in one sentence, with a concrete pain.
- **Honest limits.** "Not a good fit if you need Windows support yet." "Slower than Y on tiny inputs." Admitting a weakness is the clearest human signal.
- **Uneven rhythm.** Some short sentences. Some longer ones with a clause. Not every paragraph the same shape.
- **Restraint.** Few sections, few badges, few or no emoji, no conclusion. A 40-line README for a small tool.
- **Working examples with real output**, ideally copied from an actual run.
- **Consistent project voice.** If the maintainers write dry and terse, match it; if playful, match that. Keep existing in-jokes and names. Voice adapts; the section structure stays the one fixed in SKILL.md.
- **Structure itself is fine.** Headers, lists, tables, and thoroughness are not slop. Clear explanations are not slop. Code blocks are not slop. Do not strip useful structure in the name of sounding casual.
- **Emoji are not automatically slop.** Many pre-LLM repos used one emoji per heading to aid scanning. Meaningful and sparse is fine; decorative and dense is the tell.
- **A single em dash is not slop.** Density is.

## Final read-through questions

For each sentence:
1. Does it state a fact the reader needs?
2. Could it appear unchanged in any other project's README? If yes, rewrite with specifics or delete.
3. Is every number and capability true in the current code?
4. Would the maintainer say this out loud to a colleague?

For the whole file:
- Does the first screen show what it is, a visual, and how to try it?
- Is the README shorter than you first wrote it? It usually should be.
