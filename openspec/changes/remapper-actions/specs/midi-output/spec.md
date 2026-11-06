## ADDED Requirements

### Requirement: REQ-53 MIDI Destinations

A profile MUST accept the destinations `MidiNote` (a `channel` of 1 to 16, a `note` of 0 to 127 and a `velocity` of 1 to 127) and `MidiControlChange` (a `channel` of 1 to 16 and a `controller` of 0 to 127). A `MidiNote` MUST send note-on on press and note-off on release. A `MidiControlChange` on a button MUST send 127 on press and 0 on release, and on an axis or trigger the position scaled to 0 to 127, only when it changes. Other shapes MUST fail at load with the field path.

#### Scenario: Note on a Button

- **WHEN** `ButtonSouth` is assigned to `MidiNote` channel 1, note 60, velocity 100 and the user presses and releases it
- **THEN** the MIDI source sends `90 3C 64` and then `80 3C 00`

#### Scenario: Control Change on a Trigger

- **WHEN** `LeftTrigger` is assigned to `MidiControlChange` channel 2, controller 1, and the trigger moves from rest to full
- **THEN** the MIDI source sends `B1 01` messages with values that rise to 127 and never repeat a value twice in a row

### Requirement: REQ-54 Virtual MIDI Source

While a profile with a MIDI destination is active, OJD MUST publish one virtual CoreMIDI source named `OpenJoystickDriver`, and MUST remove it when no active profile has a MIDI destination. When CoreMIDI refuses to create the source, OJD MUST report a named error and MUST NOT activate the profile silently without MIDI.

#### Scenario: Source Follows the Profile

- **WHEN** a profile with a `MidiNote` destination is activated and then deactivated
- **THEN** a music app lists the `OpenJoystickDriver` source while it is active and does not list it afterwards

#### Scenario: Release on Deactivation

- **WHEN** a profile is deactivated while a `MidiNote` button is held
- **THEN** OJD sends the note-off before it removes the source
