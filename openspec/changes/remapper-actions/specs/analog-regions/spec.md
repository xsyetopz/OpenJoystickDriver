## ADDED Requirements

### Requirement: REQ-43 Stick Region Source

A `StickRegion` source MUST name a stick, a ring (`innerRadius` below `outerRadius`, within 0 to 1 of the deflection after the deadzone), an optional clockwise sector in degrees from up, and a `hysteresis` on the ring edges. It MUST be active while the deflection and angle lie inside. Regions of one stick MUST NOT overlap. On a move between regions, OJD MUST release the first output before it presses the second.

#### Scenario: Outer Ring as a Button

- **WHEN** a `StickRegion` of the left stick with inner 0.8 and outer 1 is assigned to key Shift and the user pushes the stick to 0.9
- **THEN** Shift is down, and it is released when the stick returns below 0.8 minus the hysteresis

#### Scenario: Eight Sectors

- **WHEN** a profile has eight non-overlapping 45 degree sectors of one ring, each assigned to a key
- **THEN** pushing the stick in one direction presses only the key of its sector

#### Scenario: Overlap

- **WHEN** two regions of the left stick share a deflection and angle
- **THEN** `ojd profile validate` rejects the profile

### Requirement: REQ-44 Trigger Band and Touch Area Sources

A `TriggerBand` source MUST name a trigger, a pressure band `from` below `to` within 0 to 1, and a hysteresis. Bands of one trigger MUST NOT overlap, and a trigger with a dual-stage mapping MUST NOT have bands. A `TouchArea` source MUST name a surface and a rectangle in surface fractions inside 0 to 1, and be active while a contact lies in it. OJD MUST reject a trigger or surface the controller does not report.

#### Scenario: Three Pressure Bands

- **WHEN** a right trigger has bands 0.1 to 0.4, 0.4 to 0.8 and 0.8 to 1, each assigned to a different key
- **THEN** pulling the trigger to 0.6 presses only the second key

#### Scenario: Touch Rectangle

- **WHEN** a `TouchArea` of the top-left quarter of the primary surface is assigned to a key and a finger rests there
- **THEN** the key is down until the finger leaves the rectangle or lifts

### Requirement: REQ-45 Region Surfaces

The Controller section of the profile editor MUST edit regions and bands, and show the live position of the stick, trigger or contact while the controller is connected. `ojd binding set` MUST accept the sources `stick-region:SIDE:INNER-OUTER[:FROM-TO]`, `trigger-band:SIDE:FROM-TO` and `touch:SURFACE:area:X:Y:W:H`. Every user-facing string MUST be a localization key in all 22 bundles.

#### Scenario: Command Line Region

- **WHEN** the user runs `ojd binding set PROFILE stick-region:left:0.8-1 key:key-a`
- **THEN** the binding is saved with a `StickRegion` source of the left stick, ring 0.8 to 1
