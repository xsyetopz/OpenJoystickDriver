# AGENTS.md

`Resources/Schemas/` is the sole owner of OpenJoystickDriver's machine-readable document contracts.

- Use JSON Schema Draft 2020-12.
- Reuse the controller, controller-override, defaults, persona, report, cli-output, profile, or error-codes schema family. `cli-output.schema.json` has one `$defs` entry per `ojd` command, named by its command path in lowerCamelCase.
- Do not add schemas scoped to one controller, consumer, diagnostic command, experiment, date, issue, pull request, or agent task.
- Keep shared parser behavior out of controller records. Schemas describe only fields emitted or consumed by an existing repository-owned interface.
- Controller records contain operational facts only. Do not add provenance, verification, confidence, evidence-level, source-note, or review-state fields or flags such as `experimental` and `needsHardwareTest`. Keep source revisions in `ControllerSources.lock.json` and accepted test observations in human-readable testing documents, issues, and Git history.
- Support reports contain observed diagnostic state only. Do not embed test plans, verification claims, inferred evidence levels, or compatibility migration payloads.
- Keep every schema strict. Prefer typed fields, enums, discriminated variants, local `$ref` values, and `additionalProperties: false`. Add length, count, or range limits only when the producer enforces the same limit.
- Schemas live in a version directory, `Resources/Schemas/v1beta1/` now, and each file declares its version through its `$id` and `$schema`. A reader accepts a fixed set of known `$schema` IDs and rejects every other ID, including one without the version segment.
- Change the one live schema for an artifact class atomically with every producer, consumer, authored input, generated output, and validation rule.
- Add a `v1`, `v2`, or later version directory only for the release that promotes or breaks the contract, and then move the live schemas there; do not keep two live versions or dated successor files. Do not retain dual writers, aliases, fallback decoders, upcasters, crosswalks, or compatibility shims.
- Follow the compatibility policy in `wiki/Controller-Records.md`.
- Do not duplicate schema field definitions or enums in handwritten validators. Code may enforce cross-document and runtime invariants only.
- Never fetch schemas at runtime. Repository validation must resolve them locally.

Validate schema changes with the repository schema/profile checks, focused producer tests, catalog regeneration checks, and `git diff --check`. Git history and releases preserve old contracts; the worktree contains only the current one. The schema gate must cover every file in both controller-record trees, not just sample controllers or schema documents.
