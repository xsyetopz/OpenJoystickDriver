# Machine-readable contracts

This directory is the only schema registry for OpenJoystickDriver-authored JSON.
Schemas use [JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12)
and are resolved locally during repository validation. Runtime code never fetches
a schema over the network.

## Schema families

- `controller.schema.json` defines generated runtime controller records.
- `controller-override.schema.json` defines authored additions and factual patches.
- `report.schema.json` defines the CloudEvents 1.0 structured JSON emitted by
  `SupportReport`.

These are repository contracts, not examples. Machine-readable producers must
declare one of these exact schemas. Documentation may explain the fields but
must not create parallel JSON formats.

`./scripts/ojd check schemas` validates every generated controller record and
every authored override against these exact contracts, then builds the app,
emits a support report, and validates that live output against `report.schema.json`.

Install the pinned validator once per checkout:

```bash
python3 -m venv .build/schema-validator
.build/schema-validator/bin/python -m pip install -r scripts/quality/requirements.txt
```

The `scripts/ojd` dispatcher automatically uses that environment for schema,
profile, and full catalog-regeneration commands.

## Evolution policy

There is exactly one live schema per artifact class. Change it in place and in
the same change update every producer, consumer, authored input, generated
output, test, and validation rule. Catalog replacement occurs only after the
complete candidate set validates.

Do not add staged `v1`, `v2`, or dated schemas. Do not add aliases, `latest`
files, migration readers, upcasters, crosswalks, dual writers, or permanent
compatibility decoders. Git history and release artifacts preserve obsolete
contracts; they do not remain live in the current worktree.

Support reports use the [CloudEvents 1.0](https://github.com/cloudevents/spec)
structured JSON envelope. `specversion`, `id`, `source`, `type`, `time`,
`datacontenttype`, and `dataschema` are CloudEvents context attributes;
OpenJoystickDriver owns only the typed `data` payload. Do not add payloads for a
hypothetical producer. Add a new report shape only with the code that emits it
and a consumer or validation test that proves the contract is live.

## Standards boundary

The schemas are prescriptive JSON Schema Draft 2020-12 contracts. Support
reports use the CloudEvents 1.0 structured envelope. Controller source
revisions are pinned separately in `ControllerSources.lock.json`; review and
hardware observations remain in human-readable testing documents, issues, and
Git history. Runtime controller records therefore contain only the operational
facts consumed by the driver, and support reports contain only observed state.

Do not invent an embedded provenance, verification, confidence, evidence-level,
test-plan, review-state, or migration vocabulary. This includes flags such as
`experimental` and `needsHardwareTest`; operational feature flags describe only
behavior consumed by the driver. If a future interoperability requirement needs
provenance, adopt a complete external standard through a separately reviewed
boundary rather than adding project-shaped fields to these contracts.

This policy follows the prior-art direction to use one prescriptive computable
model and validate every instance against it, while keeping provenance in the
system that owns derivation history rather than duplicating it into runtime
records: arXiv:2307.10034, arXiv:2511.16935, arXiv:1902.06427, and
arXiv:2211.13810.

## Prohibited formats

Never create a schema or report format for one controller, browser, consumer,
diagnostic command, issue, date, experiment, or agent session. Never commit raw
packet archives, serial numbers, HID location IDs, local filesystem paths, or
unreviewed free-form process output as a conformance report.
