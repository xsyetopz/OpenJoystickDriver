# Design

## Context

See proposal.md (Why). The readers today:

| Reader | Parse |
| --- | --- |
| `ControllerRecordSet.loadCatalog` (bundle, `OJDRepositoryTool validate controllers`) | `requireUTF8`, `JSONSerialization`, `OrderedJSON.parse` |
| `ControllerRecordSet.parse` (user folder, packages, `ojd record install`, `ojd config`, Library) | `requireUTF8`, `JSONSerialization` (for the header check), `OrderedJSON.parse` |
| `RepositoryValidation` record and patch files (`apply-patches`) | `requireUTF8`, `OrderedJSON.parse`, `JSONSerialization` |
| `ControllerDefaults.validate` (`all.patch.json`) | `requireUTF8`, `JSONSerialization`, `OrderedJSON.parse` |
| `ModPackageStore.requireKind` | `JSONSerialization` for `kind` only |
| `ControllerRecordProbePlan` (`ojd diagnose record`) | `JSONDecoder` only |
| `SystemGamepadSupportAudit.bundledOJDRecords` | scans the bundle, `JSONDecoder` of a two-field struct |
| `VirtualDevice.decode` | `JSONSerialization`, then hand-written checks on `[String: Any]` |

The `JSONSerialization` pass before `OrderedJSON.parse` was kept in commit 54398ba4b when the merge moved to `OrderedJSON`; its result is discarded. `OrderedJSON.parse` already refuses a byte order mark, UTF-16 text, invalid syntax and a duplicate member.

## Goals / Non-Goals

**Goals:**

- `OrderedJSON.parse` is the only text reader of Controller and ControllerPatch files.
- One typed decode for VirtualDevice files, with the strict-key helpers the profile and record decoders use.

**Non-Goals:**

- The typed decode of a merged record (`ControllerRecordSet.decode`: `foundationValue()`, `JSONSerialization.data`, `JSONDecoder`) stays. It decodes an in-memory merge, not a file, and replacing it needs a `Decoder` over `OrderedJSON`, which costs more than it removes.
- `ControllerRecordWriter`'s edit of `[String: Any]` stays; it runs after `validate` has accepted the file.
- Profiles, Settings, AccessGrants, mod.json and the endpoint wire format already use one `JSONDecoder` each and are untouched.
- Replacing a bundled record with a whole user file stays refused; a patch changes or deletes (`null`) any member.

## Decisions

### D1 Documents stay JSON; no property lists, no JavaScriptCore

Property lists and JavaScriptCore generators were weighed as the authoring format and rejected:

- **Patches.** Patches delete a member with RFC 7396 `null`, and a property list has no null.
- **Member order and number text.** `OrderedJSON` keeps both so that `ojd config set` writes a minimal diff. Property-list dictionaries have no order.
- **Validation for others.** The published JSON Schemas (`$id` under `schemas/v1alpha2/`) give editors, CI, the SDK and other-language clients a contract. A property list has no schema language.
- **The core must stay neutral.** `check_neutral_core_imports.py` allows the Kit only `CryptoKit`, `Darwin`, `Dispatch` and `Foundation`, so JavaScriptCore could not run in the core.
- **User scripts cannot be stopped.** The public JavaScriptCore headers (`JSContext.h`, `JSContextRef.h`) have no execution time limit, so a user script that never ends would hang its host.
- **No second format before v1.0.0.** AGENTS.md allows one format before v1.0.0, without migrations. Keeping JSON beside a property list during a switch breaks that.

Alternative considered: a binary property-list cache of the generated catalog. It is not taken: it would add a second artifact for the 696 records, and load time has not been measured as a problem.

### D2 Remove the `JSONSerialization` pre-pass

Delete `ControllerRecordSet.jsonObject` and each `_ = try jsonObject(data)`. The header check in `parse` reads `apiVersion` and `kind` from the `OrderedJSON` document. To make that possible, `OpenJoystickDriverAPI.requireHeader` gains an overload taking the two values, which `headerProblem(apiVersion:kind:expected:)` already accepts.

- `ControllerDefaults.validate` drops its `is [String: Any]` check; `ordered(data)` plus a check that the root is an object replace it.
- `ModPackageStore.requireKind` reads `kind` from `OrderedJSON.parse`. When the parse fails, it leaves the file to the record validation, as it does today.

Alternative considered: keep `JSONSerialization` as the only parser and drop `OrderedJSON`. Rejected because the merge and the writer need member order and number text.

### D3 The probe reads a record like the catalog does

`ControllerRecordProbePlan.init(data:)` calls `ControllerRecordSet.requireUTF8`, `ordered` and `decode`. It does not call `parse`: `parse` refuses a bundled model, and probing a bundled model is a supported use.

### D4 The audit uses the loaded catalog

`bundledOJDRecords()` returns `ControllerRecordSet.bundled.records.keys.sorted()`. The bundled set is already loaded and checked, and loading it fails the process on an invalid bundled file. A bundled file the audit used to skip silently can no longer exist.

### D5 VirtualDevice decodes through `Decodable`

`VirtualDevice.Document: Decodable` uses `rejectUnknownKeys` and keeps the header check first, so a wrong `apiVersion` or `kind` stays E5001. `DecodingError` maps to E5007 through `ControllerRecordSet.problemDescription`, like records. The persona/match rules stay as checks after decoding, with their current messages.

## Risks / Trade-offs

- [Error text changes for invalid JSON: the `JSONSerialization` message gives way to the `OrderedJSON` problem with its offset] → Codes are unchanged. Update any test that compares the full text, and record the change in CHANGELOG.
- [`OrderedJSON.parse` accepts something `JSONSerialization` refused] → Add parity tests for each of these and confirm both refuse them:
  - deep nesting;
  - lone surrogate escapes;
  - control characters in strings;
  - leading zeros;
  - a trailing comma;
  - `NaN`.
- [VirtualDevice messages for wrong types change wording] → Keep the code. Tests assert codes and the stable parts of the messages.
