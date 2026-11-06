## ADDED Requirements

### Requirement: A pad report shows presence

A receiver slot SHALL be connected when the receiver reports a controller in that slot or when the slot delivers a valid pad report. The slot SHALL NOT send the presence inquiry again because of pad reports that arrive without a presence report.

#### Scenario: Pad report before presence report

- **WHEN** a slot that has not reported presence delivers a valid pad report
- **THEN** the slot becomes connected, the pad report is decoded, and no output is queued

#### Scenario: Malformed report

- **WHEN** a slot delivers a report shorter than a pad report or with a wrong inner type
- **THEN** the slot stays disconnected

#### Scenario: Controller leaves

- **WHEN** the receiver reports that the controller left the slot
- **THEN** the slot becomes disconnected and its state returns to neutral

### Requirement: Power-off is a named behavior

The receiver power-off packet SHALL be sent only for a slot with a connected controller and only when the session is closed on purpose, including system sleep. It SHALL NOT be sent after an input or output error or when the device is unplugged. When the behavior is enabled, the user-facing text SHALL say that closing the app turns a wireless pad off.

#### Scenario: Deliberate close

- **WHEN** the session of a connected slot is stopped
- **THEN** the power-off packet is written once before the interface is released

#### Scenario: Transfer error

- **WHEN** the session of a connected slot ends because a transfer failed
- **THEN** no power-off packet is written

#### Scenario: Empty slot

- **WHEN** the session of a slot with no controller is stopped
- **THEN** no power-off packet is written

### Requirement: Guide hold turns the pad off

Holding Guide on a connected receiver slot for the configured number of seconds SHALL send the power-off packet once. A value of 0 SHALL turn the behavior off.

#### Scenario: Hold reaches the limit

- **WHEN** Guide stays down for the configured number of seconds
- **THEN** the power-off packet is written once

#### Scenario: Release before the limit

- **WHEN** Guide is released before the configured number of seconds
- **THEN** no power-off packet is written

### Requirement: A receiver held by another process is named

When another process holds the receiver, OJD SHALL report the state `ownedByAnotherClient` with the holder's name when known, SHALL NOT write to the device, and SHALL open it when the holder releases it.

#### Scenario: Steam holds the receiver

- **WHEN** OJD starts while Steam holds the receiver
- **THEN** the controller shows that another application uses it, and no timed retry runs

### Requirement: Slot order follows interface number

A receiver SHALL give one slot to each qualifying interface in ascending interface number, up to four. An interface past the fourth SHALL NOT become a slot.

#### Scenario: Interleaved audio interfaces

- **WHEN** a receiver lists interfaces 0 to 7 and only 0, 2, 4 and 6 have the receiver class triple
- **THEN** interfaces 0, 2, 4 and 6 are slots 1 to 4
