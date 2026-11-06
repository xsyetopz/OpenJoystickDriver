## ADDED Requirements

### Requirement: Clone start sequence is gated by device strings

A wired Xbox 360 controller record MAY list vendor control reads that run before the first input read. They SHALL run only when the device's strings and release match the entry's gate. A device whose manufacturer string differs, or is missing, SHALL NOT receive them.

#### Scenario: SHANWAN clone

- **WHEN** a device with ID `045e:028e` and manufacturer `SHANWAN` starts a session
- **THEN** the three control reads `C1 01 0100 0000 20`, `C1 01 0000 0000 8` and `C0 01 0000 0000 4` (request type, request, value, index, length) are sent in order before the first input read

#### Scenario: Genuine controller

- **WHEN** a device with ID `045e:028e` and manufacturer `Microsoft` starts a session
- **THEN** no control read is sent

#### Scenario: Rejected read

- **WHEN** a control read of the sequence is rejected
- **THEN** the rejection is logged, the remaining reads still run, and the session starts
