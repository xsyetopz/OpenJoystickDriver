# Schema limit audit

Source: the `description` text that tasks 7.1 and 7.2 removed or shortened (`schema-style-dropped-limits.md` lists it). Each limit is one row. Enforcement is one of:

- K: a schema keyword (`file:line`).
- W: a wiki sentence plus a rejection case. `schema: true` means the JSON Schema alone rejects the case. `schema: false` means only the Swift validator does.
- P: a producer or runtime fact. The schema cannot decide it, and the producer line is named.
- F: a fact about meaning, not a limit on a value. No check applies.

Lines are those of the tree after this commit.

## access-grants.schema.json

| Limit | Enforced |
| --- | --- |
| `controlGrantedAt` present exactly when the grant is marked | K `access-grants.schema.json:70,177-189` (`controlIsMarked`) |
| Grant publisher kind is one of the listed values | K `access-grants.schema.json:13,123,134` |
| Token fields and port range | K `access-grants.schema.json:56` (`maximum` 65535) |
| Empty origin list is allowed | K by absence of `minItems` |
| Only the service writes the file | F |

## cli-output.schema.json

| Limit | Enforced |
| --- | --- |
| Publication fields depend on the publisher | K existing `if`/`then` |
| `serverSource` is one of the listed values | K existing `enum` |
| `controllerWatch` is one shape out of several | K `cli-output.schema.json:1180` (`oneOf`) |
| `profileValidate` is one shape out of several | K `cli-output.schema.json:1997` (`oneOf`) |
| W3C entry source matches a pattern | K `cli-output.schema.json:3818` |
| Virtual feed line is one shape out of several | K existing `oneOf` |
| `serving.reason` only with route `OutputDisabled` | K `cli-output.schema.json:1034` (added) |
| `serving.persona` absent for `NativePassThrough` and `OutputDisabled`, present otherwise | K `cli-output.schema.json:1049` (added) |
| `migrate` item `detail` only with status `Failed` | K `cli-output.schema.json:1640` (added) |
| Socket token has no `origin` | K `cli-output.schema.json:2603` (added) |
| `commandLineTool.target` absent for `Missing` and `BlockedByFile`, present otherwise | K `cli-output.schema.json:3921` (added) |
| A diagnose timing lists at most 8 frames | K `cli-output.schema.json:1275` (added) |
| A virtual SDL GUID is `03` or `05` plus 24 hex digits | K `cli-output.schema.json:3781` (added) |
| Summary `frames` at most 15000 | K `cli-output.schema.json:3097` (added) |
| No `lastSeconds` means no `stalls` and no `ReadToRead` gap; one frame or fewer means no `stalls` | K `cli-output.schema.json:3044` (added) |
| A running service has no `listenerFailure` or `listenerFailureProblem` | K `cli-output.schema.json:4027` (added) |
| A `Driver` layer value has no `value`; other layers have one | K `cli-output.schema.json:392` (added) |
| A controller query has no `families` in its values | K `cli-output.schema.json:348` (added) |
| `configShow` `controller`, `profile`, `defaultsProblem`; `power`; `unit`; `inputMapping`; `record`; `tuning`; watch output; config-change `controller`, `previous`, `value`; token `name`; `exclusiveOwner` and `processID`; watched controller input and output; virtual show `sdl` and `w3c`; `duration` are present only when the producer has a value | P optional properties with no discriminator; producers `ControllerReport.swift`, `StatusReport.swift:50-84,236-262`, `ConfigCommand.swift:205-241`, `ProtocolClassifier.swift:343`, `FrameTimingSummary.swift:112-157` |
| `sharedExclusiveOwner.name` is truncated | F, the name can be a kernel driver class, so it has no `maxLength` (`USBExclusiveOwner.swift`) |
| Clock and window semantics, digital triggers, `outputOwner`, the stall threshold of 3 times the median, Y axis direction | F |

## report.schema.json

| Limit | Enforced |
| --- | --- |
| A controller lists at most 8 frame timings | K `report.schema.json:257` (added) |
| Summary `frames` at most 15000 | K `report.schema.json:173` (added) |
| No `lastSeconds` means no `stalls` and no `ReadToRead` gap; one frame or fewer means no `stalls` | K `report.schema.json:120` (added) |
| `notes` and `warnings` come from the support report and the gamepad audit | P `SupportReport.swift:338-347`, `SystemGamepadSupportAudit.swift:172,303-319` |

## settings.schema.json

| Limit | Enforced |
| --- | --- |
| Defaults and the conditional fields | K `settings.schema.json` (7.3 commit), `test_settings_schema.py` |

## profile.schema.json

| Limit | Enforced |
| --- | --- |
| Profile name is 1 to 80 characters, no outer space, no control character | K `profile.schema.json:127-128`; rejection cases in `ProfileSchemaTests.swift`, "profile name over 80 characters", "profile name with a control character", "profile name with a space at the end" (the schema and the decoder both reject them) |
| Layer name is 1 to 40 characters, same rule | K `profile.schema.json:1036-1037`; cases "layer name over 40 characters", "layer name with a control character" |
| `OpenURL` URL is absolute and not `file` | K `profile.schema.json:712` (pattern) |
| `Keyboard` `modifiers` are a set | W wiki sentence corrected; the decoder reads a `Set` and the encoder sorts (`Destination.swift:214-217,292`) |
| Keyboard keys, modifiers, MIDI ranges, turbo ranges, deadzones | K existing `enum`, `minimum`, `maximum` |
| Cross-field rules: pulse duration, gyro activation source, `Off` effect, hysteresis, deadzones, thresholds, grid, region, band, layer activators | W `wiki/Profile-File-Reference.md` "Rules Across Fields"; decoder-only cases in `ruleAcrossFieldsRefusedByDecoderOnly` (the test asserts the schema accepts them, so they are `schema: false` in effect); the gyro `activationSource` rule and the `Off` effect rule are keywords in the schema, with cases "gyro activation source with the Always mode" and "Off adaptive trigger effect with a strength" in `aBrokenProfileIsRejectedByTheDecoderAndTheSchema` |
| `ProfileSwitch` model, `Speak` voice, touch region bounds, stick region overlap, trigger band overlap, region direction | W wiki sentence; cases in `ProfileRuleRejectionTests.swift`, each with its own fixture and `schema: false` (the schema accepts each document): `profileSwitchToAnotherModelRefusedByLibraryCheckOnly` (`validateProfileSwitches`, `ProfileControl.swift:126`), `speakVoiceMacLacksRefusedByLibraryCheckOnly` (`validateSpeechVoices`, `ProfileControl.swift:111-112`), "touch region past the right edge" and "touch region past the bottom edge" (`Profile+Validation.swift:321`), "stick regions overlap in radius", "in angle", "across 0 degrees" (`Profile+RegionValidation.swift:27`), "trigger bands overlap" (same line), "stick region with equal angles" (`Profile+Validation.swift:314`); the first two need the other profiles or the Mac voice list, so the library check runs them, not `load` |

## controller, protocol-description, controller-patch

Rule entries of these schemas are enforced by the Swift validator. Each has a rejection case in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`. `test_schema_rejection_flags.py` checks the `schema` flag of each.

## Counts

The tables above hold 38 rows (the controller and protocol-description rule entries are counted once, outside the rows).

- Already enforced before this commit: 14 rows (K existing 4 + 6 + 1 + 1 in access-grants, cli-output and settings, the OpenURL pattern, the profile enums, and the cross-field wiki list).
- Added in this commit: 17 keywords (12 in `cli-output.schema.json`, 3 in `report.schema.json`, 2 name `maxLength` plus control-character patterns in `profile.schema.json`), 5 profile name cases, 3 more cross-field cases (1 decoder-only, 2 that the schema also rejects), and the corrected `modifiers` sentence.
- Not checkable by a schema: 3 meaning facts (F) and 2 producer-determined groups (P) in the tables.
