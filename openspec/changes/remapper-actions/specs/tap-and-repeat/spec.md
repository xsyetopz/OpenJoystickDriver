## ADDED Requirements

### Requirement: REQ-32 Tap Counts from Two to Five

An action MUST accept a `multiTap` list in place of `doubleTap`. An entry has a `count`, a `windowMs` and a destination; counts are unique. The window runs from one tap's release to the next press. OJD MUST reject `doubleTap` as an unknown key. An entry keeps the limits of double tap. The count range 2 to 5 is proposed; the window range is the double-tap range in `wiki/Bindings-and-Actions.md`.

#### Scenario: Triple Tap

- **WHEN** an action has a `multiTap` entry of count 3 and the user taps the source three times, each press within `windowMs` of the last release
- **THEN** the entry's destination fires once

#### Scenario: Count Not Reached

- **WHEN** an action has entries for counts 2 and 3 and the user taps twice and waits longer than `windowMs`
- **THEN** only the count 2 destination fires

#### Scenario: Removed Key

- **WHEN** a profile file has `doubleTap` on an action
- **THEN** OJD rejects the file as an invalid profile

### Requirement: REQ-33 Tap Resolution Is Visible and Bounded

When an action has `multiTap` entries, the base destination MUST fire if no further tap follows within the longest `windowMs` among its entries; OJD MUST NOT drop a tap. The editor and `ojd binding list` MUST show the added delay (the longest `windowMs`) on the base destination of such an action.

#### Scenario: Delay Shown

- **WHEN** an action has `multiTap` entries with windows of 200 ms and 300 ms
- **THEN** the editor and `ojd binding list` show that the base destination can wait 300 ms

### Requirement: REQ-34 Repeat with Initial Delay and Count

`turbo` MUST accept `initialDelayMs` from 0 to 2500 (0 when omitted) and `maxRepeats` from 1 to 500 (omitted means repeat while held). The press itself is not a repeat. The first repeat MUST start `initialDelayMs` or one turbo period after the press, whichever is later; later repeats follow the `turbo` rate and duty. When `maxRepeats` is reached, repeating MUST stop until the source is released and pressed again. The existing turbo limits MUST still apply.

#### Scenario: Delay before Repeat

- **WHEN** a key action has turbo with `initialDelayMs` 400 and the user holds the source
- **THEN** the key goes down once at the press, and the first repeat starts no earlier than 400 ms after the press

#### Scenario: No Delay

- **WHEN** turbo has `initialDelayMs` 0 and the user holds the source
- **THEN** the first repeat starts one turbo period after the press, as turbo without the field does

#### Scenario: Repeat Cap

- **WHEN** turbo has `maxRepeats` 5 and the user holds the source for longer than five turbo periods
- **THEN** the destination goes down at the press, repeats five more times, and then repeats no more until the next press

### Requirement: REQ-35 Tap and Repeat Surfaces

The behavior sheet MUST edit `multiTap` entries and the turbo delay and cap. `ojd binding set` MUST accept `--multi-tap COUNT:MS:TARGET` (repeatable), `--turbo-delay MS` and `--turbo-max COUNT`, and MUST reject `--double-tap`. Every user-facing string MUST be a localization key in all 22 bundles.

#### Scenario: Command Line Triple Tap

- **WHEN** the user runs `ojd binding set PROFILE button:south key:key-a --multi-tap 3:300:key:key-b`
- **THEN** the binding has a `multiTap` entry of count 3, window 300 ms and key B
