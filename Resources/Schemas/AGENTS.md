# AGENTS.md

`Resources/Schemas/` owns every machine-readable document contract.

- JSON Schema Draft 2020-12, flat files `<kind>.schema.json`, one live version, strict (`additionalProperties: false`, enums, typed fields, local `$ref`). Limits only where the producer enforces them.
- Reuse an existing family (controller, controller-patch, virtual-device, mod-package, protocol-description, settings, report, cli-output, profile, error-codes). No schemas scoped to one controller, consumer, command, date, issue or task. `cli-output` has one lowerCamelCase `$defs` entry per `ojd` command.
- `vocabulary.schema.json` alone defines control ids (UpperCamelCase `$defs/control`); the Swift `Control` enum mirrors it under test. `Resources/Vocabulary/crosswalk.json` is documentation, never an alias.
- Every kind requires `apiVersion: openjoystickdriver/v1alpha2` and an UpperCamelCase `kind` by `const`; no `$schema` in instances. Readers reject a missing or unknown version naming file, found and supported version.
- `$id` is `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha2/<kind>.schema.json`. Sources: `Scripts/Catalog/schema_header.py` for the `$id`, and `OpenJoystickDriverAPI.version` for the `apiVersion`, which Python reads through `OJDRepositoryTool facts`. Raise the version only for a release that breaks the contract.
- Records hold operational facts only: no provenance, confidence, verification or `experimental` flags. Reports hold observed state only.
- Change a schema atomically with every producer, consumer, input, generated output and rule. No duplicated enums in handwritten validators; code enforces cross-document invariants only. Never fetch schemas at runtime.
- Follow the version rules in `wiki/Controller-Records.md`.
- Validate with schema/profile checks, producer tests, `catalog regenerate --check` and `git diff --check`, across every file in both record trees.
