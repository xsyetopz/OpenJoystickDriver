## ADDED Requirements

### Requirement: Migrate Stale Documents

`ojd migrate` SHALL convert every stored document of the support directory whose `apiVersion` is an
older version into the current version: `Settings.json`, `AccessGrants.json`, profiles, the user's
controller records and patches, and virtual device files. It SHALL check the converted document with
the current reader before it writes, write it atomically, and keep the original in the `Migrated`
folder of the support directory. It SHALL NOT convert an installed mod.

#### Scenario: Stale Profile

- **WHEN** `Profiles/` holds a `v1alpha1` profile with a `doubleTap` binding and the user runs
  `ojd migrate`
- **THEN** the profile file has the current `apiVersion` and a `multiTap` entry with `count` 2, it
  loads, and the original is in `Migrated/`

#### Scenario: Dry Run

- **WHEN** the user runs `ojd migrate --dry-run`
- **THEN** it lists each document it would convert and writes nothing

#### Scenario: Current Documents

- **WHEN** no document is stale
- **THEN** `ojd migrate` reports that there is nothing to migrate and exits 0

### Requirement: Unconvertible Documents Stay Unchanged

A document with no mechanical mapping SHALL be reported with a named error, left unchanged, and be
refused with `E5001` on load. The remaining documents SHALL still be converted.

#### Scenario: Patch Without Report

- **WHEN** a `v1alpha1` controller patch sets `input.buttons` but no `input.report`
- **THEN** `ojd migrate` reports `E5009` for that file, leaves it unchanged, and exits 1

### Requirement: App Offers Migration

Where the app shows `E5001` for a document a step converts, it SHALL offer a **Migrate** action
that runs the same conversion and then retries.

#### Scenario: Refused Settings at Launch

- **WHEN** the app starts with a `v1alpha1` `Settings.json`
- **THEN** the alert offers **Migrate** and, after it, the app starts with the converted settings
