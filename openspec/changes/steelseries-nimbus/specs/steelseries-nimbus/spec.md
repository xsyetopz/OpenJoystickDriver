## ADDED Requirements

### Requirement: Nimbus Input From Its Descriptor

OpenJoystickDriver SHALL read the SteelSeries Nimbus (`1038:1420`, USB) from its HID descriptor: the D-pad and the first six buttons as digital controls at a pressure threshold, L2 and R2 as analog triggers, Consumer `0x0223` as Menu, and the four stick axes with stick Y inverted. The record SHALL leave the pad to macOS and publish no virtual controller for it.

#### Scenario: Button Pressure Crosses the Threshold

- **WHEN** a button or D-pad byte reaches full pressure
- **THEN** the mapped control is pressed
- **AND** a byte at low pressure leaves it released

#### Scenario: Stick at Rest

- **WHEN** the left stick Y byte rests near -3
- **THEN** the stick reads centered

#### Scenario: Triggers Are Analog

- **WHEN** the L2 or R2 byte rises
- **THEN** the trigger value rises with it and no digital trigger press is listed

### Requirement: D-pad Usages Map on the Descriptor Path

A HID descriptor controller that declares Generic Desktop usages `0x90` to `0x93` SHALL report Up, Down, Right and Left when the value passes half the range from its center, and an SDL button binding for a D-pad direction SHALL read the same way.

#### Scenario: Pressure D-pad

- **WHEN** usage `0x92` reads 255 on a 0 to 255 range
- **THEN** the D-pad reads Right

### Requirement: Controls List Follows the Descriptor

The controls that a HID descriptor controller lists SHALL be the controls its usage map drives from usages the descriptor declares, and SHALL NOT include Back, Start or a stick click that neither declares.

#### Scenario: SDL-Mapped Pad Without Back

- **WHEN** an SDL mapping covers a pad whose descriptor has no Back, Start or stick-click usage
- **THEN** its controls list holds none of them
