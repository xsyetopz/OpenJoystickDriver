## ADDED Requirements

### Requirement: REQ-55 Speak Destination

A profile MUST accept the destination `Speak` with a `text` of 1 to 128 characters and an optional `voice`, a voice identifier that `AVSpeechSynthesisVoice` knows. A press MUST speak the text once. A press while the same destination is still speaking MUST stop it and speak the text again from the start; this behavior is named `RestartOnPress`. OJD MUST reject at load an empty or longer text and a `voice` that the Mac does not have, with the invalid-profile error and the field path.

#### Scenario: Speak on Press

- **WHEN** `ButtonNorth` is assigned to `Speak` with the text `Reloading` and the user presses it
- **THEN** the Mac speaks "Reloading" once

#### Scenario: Unknown Voice

- **WHEN** a profile names a `voice` that is not installed
- **THEN** `ojd profile validate` rejects the profile and names the destination and the voice

### Requirement: REQ-56 Speech Stops with the Profile

When the profile that owns a speaking `Speak` destination is deactivated or paused, OJD MUST stop the speech at once.

#### Scenario: Pause While Speaking

- **WHEN** remapping is paused while a `Speak` destination is speaking
- **THEN** the speech stops
