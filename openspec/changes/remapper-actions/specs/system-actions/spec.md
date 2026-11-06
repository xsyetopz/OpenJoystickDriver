## ADDED Requirements

### Requirement: REQ-36 System Key Destination

A `SystemKey` destination MUST send one system-defined key event through the public Core Graphics event API, with key codes from the public `ev_keymap.h` header: `PlayPause`, `NextTrack`, `PreviousTrack`, `FastForward`, `Rewind`, `VolumeUp`, `VolumeDown`, `Mute`, `BrightnessUp`, `BrightnessDown`, `KeyboardIlluminationUp`, `KeyboardIlluminationDown`. A press sends key down and a release sends key up. OJD MUST NOT call a private framework.

#### Scenario: Volume Up

- **WHEN** a button is assigned to `SystemKey` `VolumeUp` and the user presses it with Post Event access granted
- **THEN** macOS raises the output volume and shows its volume indicator

#### Scenario: Unknown Key

- **WHEN** a profile file has a `SystemKey` name outside the list
- **THEN** OJD rejects the file as an invalid profile

### Requirement: REQ-37 Mission Control and Application Actions

`SystemAction` `MissionControl` MUST open the Mission Control application through `NSWorkspace`. `OpenApplication` (a bundle identifier) and `OpenURL` (any absolute URL with a scheme) MUST open through `NSWorkspace`; `RunShortcut` (a shortcut name of 1 to 50 characters) MUST run `/usr/bin/shortcuts run`. OJD MUST reject at load a URL that does not parse or has no scheme. When a target is not found or the run fails, OJD MUST report a named error and MUST NOT do nothing.

#### Scenario: Open an Application

- **WHEN** a button is assigned to `OpenApplication` with `com.apple.TextEdit` and the user presses it
- **THEN** TextEdit opens or comes forward

#### Scenario: Rejected URL Scheme

- **WHEN** a profile has an `OpenURL` destination with the text `not a url`
- **THEN** `ojd profile validate` rejects the profile and names the destination

#### Scenario: Missing Shortcut

- **WHEN** the user presses a source assigned to `RunShortcut` with a name that does not exist
- **THEN** OJD reports an error that carries the shortcut name, in the Activity area and in `ojd log`

### Requirement: REQ-38 Type Text

A `TypeText` destination MUST hold 1 to 128 characters. OJD MUST type the text through Core Graphics Unicode key events, in order, without a modifier left down. When secure event input is enabled in macOS, OJD MUST NOT type; it MUST report a named error that tells the user that a secure field has input. A `TypeText` destination MUST be rejected with any behavior other than a press.

#### Scenario: Type a Phrase

- **WHEN** a button is assigned to `TypeText` `hello` and the user presses it with a text field focused
- **THEN** the field receives `hello`

#### Scenario: Secure Input

- **WHEN** the user presses the button while a password field has focus
- **THEN** nothing is typed and OJD reports the named secure-input error

### Requirement: REQ-39 System Action Surfaces

The assignment editor MUST offer each destination of REQ-36 to REQ-38. `ojd binding set` MUST accept the targets `system-key:NAME`, `system:mission-control`, `open-app:BUNDLE-ID`, `open-url:URL`, `shortcut:NAME` and `text:STRING`. The macOS implementation MUST live outside the core, behind a protocol the core declares.

#### Scenario: Command Line Target

- **WHEN** the user runs `ojd binding set PROFILE button:north system-key:volume-up`
- **THEN** the binding is saved with a `SystemKey` destination of `VolumeUp`
