## ADDED Requirements

### Requirement: REQ-46 Pointer Speed Driver

A profile MUST accept an optional `pointerSpeed`: a `driver` (trigger pressure or stick depth, left or right), `minScale`, `maxScale` and a `curve`. OJD MUST multiply all pointer movement (stick and touch pointer modes, gyro mouse, `MouseMovement`) by the scale the curve gives for the driver, `minScale` at 0 and `maxScale` at 1. Scroll MUST NOT change. OJD MUST reject a driver the controller does not report. The scale range 0 to 10 is proposed.

#### Scenario: Slow Down by Trigger

- **WHEN** `pointerSpeed` has driver left trigger, `minScale` 1 and `maxScale` 0.25 with a linear curve, and the trigger is fully pulled while the right stick moves the pointer
- **THEN** the pointer moves at one quarter of its speed with the trigger released

#### Scenario: Speed by Stick Depth

- **WHEN** `pointerSpeed` has driver right stick depth, `minScale` 0.5 and `maxScale` 2, and the stick drives gyro-free pointer movement at half depth
- **THEN** the pointer scale is 1.25 on a linear curve

#### Scenario: Scroll Unchanged

- **WHEN** a pointer speed is set and the user scrolls with a scroll destination
- **THEN** the scroll amount is the same as with no pointer speed

### Requirement: REQ-47 Pointer Speed Surfaces

The Controller section MUST edit `pointerSpeed` and show the current scale while the controller is connected. `ojd profile set PROFILE pointerSpeed JSON` MUST set it, and `ojd binding` MUST NOT need a new target. Every user-facing string MUST be a localization key in all 22 bundles.

#### Scenario: Set on the Command Line

- **WHEN** the user runs `ojd profile set PROFILE pointerSpeed '{"driver":{"type":"Trigger","side":"Left"},"minScale":1,"maxScale":0.25,"curve":"Linear"}'`
- **THEN** the profile validates and saves
