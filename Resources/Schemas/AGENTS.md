# Schema instructions

`Resources/Schemas/` is the sole owner of OpenJoystickDriver's machine-readable
document contracts.

- Use JSON Schema Draft 2020-12.
- Reuse the controller, controller-override, or report schema family.
- Do not add schemas scoped to one controller, consumer, diagnostic command,
  experiment, date, issue, pull request, or agent task.
- Do not encode shared parser behavior in controller records. Schemas describe
  only fields emitted or consumed by an existing repository-owned interface.
- Controller records contain operational facts only. Do not add provenance,
  verification, confidence, evidence-level, source-note, or review-state fields
  or flags such as `experimental` and `needsHardwareTest`. Keep source revisions
  in `ControllerSources.lock.json` and accepted test observations in
  human-readable testing documents, issues, and Git history.
- Support reports contain observed diagnostic state only. Do not embed test
  plans, verification claims, inferred evidence levels, or compatibility
  migration payloads.
- Keep every schema strict. Prefer typed fields, enums, discriminated variants,
  local `$ref` values, and `additionalProperties: false`. Add length, count, or
  range limits only when the producer enforces the same limit.
- Change the one live schema for an artifact class atomically with every
  producer, consumer, authored input, generated output, and validation rule.
- Do not stage `v1`, `v2`, or dated successor files. Do not retain dual writers,
  aliases, fallback decoders, upcasters, crosswalks, or compatibility shims.
- Do not duplicate schema field definitions or enums in a second handwritten
  validator. Code may enforce cross-document and runtime invariants only.
- Never fetch schemas at runtime. Repository validation must resolve them locally.

Validate schema changes with the repository schema/profile checks, focused
producer tests, catalog regeneration checks, and `git diff --check`. Git history
and releases preserve old contracts; the worktree contains only the current one.
The schema gate must cover every file under both controller-record trees; do not
validate only a sample controller or only the schema documents themselves.
