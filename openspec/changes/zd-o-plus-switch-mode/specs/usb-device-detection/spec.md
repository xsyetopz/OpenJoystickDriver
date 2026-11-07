## ADDED Requirements

### Requirement: Diagnose Reports a Pro Controller Look-Alike

`ojd diagnose` SHALL report a connected `057E:2009` controller whose USB serial number is `000000000001` in a named check, with a message that says the pad reports the identity and serial of a Nintendo Switch Pro Controller and that other pads may report the same serial. The check SHALL NOT change which driver binds the pad.

#### Scenario: Placeholder Serial

- **WHEN** a `057E:2009` controller with serial `000000000001` is connected
- **THEN** the check warns and names the VID:PID and the serial (`diagnoseWarnsOnPlaceholderSwitchSerial`)

#### Scenario: Other Serial

- **WHEN** a `057E:2009` controller has another serial or none
- **THEN** the check passes (`diagnosePassesOtherSwitchSerial`)

#### Scenario: Other Identity

- **WHEN** no `057E:2009` controller is connected
- **THEN** the check is absent or skipped (`diagnoseSkipsWithoutSwitchIdentity`)
