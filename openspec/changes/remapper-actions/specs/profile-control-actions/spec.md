## ADDED Requirements

### Requirement: REQ-40 Switch Profile, Set Layer, Pause

`ProfileSwitch` (a profile id, `Next` or `Previous`), `LayerSet` (a layer of the same profile and `On`, `Off` or `Toggle`) and `Pause` (`On`, `Off` or `Toggle`) MUST fire on the press of their source; OJD MUST reject another behavior. A `ProfileSwitch` id MUST name a profile for the same controller model. `Next` and `Previous` MUST walk the profiles of the same model and scope in case-insensitive name order and wrap around.

#### Scenario: Switch to a Named Profile

- **WHEN** a button is assigned to `ProfileSwitch` to profile B and profile A is active for the model
- **THEN** profile B becomes the active profile for that model and scope, as `ojd profile activate B` makes it

#### Scenario: Profile for Another Model

- **WHEN** a `ProfileSwitch` names a profile for a different controller model
- **THEN** `ojd profile validate` rejects the profile and names the destination

#### Scenario: Layer Toggle

- **WHEN** a button is assigned to `LayerSet` with mode `Toggle` and the user presses it twice
- **THEN** the layer is active after the first press and inactive after the second

### Requirement: REQ-41 Pause Behavior and Visible State

While a controller is paused, OJD MUST send the output that the controller has with no profile active, except that assignments with a `Pause` destination MUST stay active. A pause MUST release every output the profile holds, including macros (REQ-29). The pause state MUST be per controller, MUST show in the Controllers area, in `ojd status` and in the status item, and MUST clear when the active profile changes, the controller disconnects, or the service restarts.

#### Scenario: Pause and Resume

- **WHEN** the user presses a button assigned to `Pause` `Toggle` twice
- **THEN** the controller passes through unchanged after the first press and runs the profile again after the second

#### Scenario: Pause Shown

- **WHEN** a controller is paused
- **THEN** `ojd status` and the Controllers area show it as paused

### Requirement: REQ-42 Profile Control Surfaces

The assignment editor MUST offer the three destinations. `ojd binding set` MUST accept `profile:switch:ID|next|previous`, `layer:NAME:on|off|toggle` and `pause:on|off|toggle`. Each switch MUST add an entry to the Activity log with the old and new profile names. Every user-facing string MUST be a localization key in all 22 bundles.

#### Scenario: Activity Entry

- **WHEN** a `ProfileSwitch` runs
- **THEN** the Activity log shows the profile name before and after
