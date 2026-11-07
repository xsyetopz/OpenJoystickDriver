## ADDED Requirements

### Requirement: REQ-27 Macro Document

A profile MUST hold named macros. A macro MUST have an `id`, a `name` unique in the profile, `steps`, a `repeat` (a count or `WhileHeld`), `whileRunning` (`Ignore` or `Restart`) and `interruptOnRelease`. A step MUST be `Tap`, `Press`, `Release`, `Chord` with a hold time, or `Wait`. OJD MUST reject any other shape with the invalid-profile error and the field path. The limits are 16 macros per profile, 32 steps, a repeat count of 1 to 500 and a wait of 0 to 5000 ms.

#### Scenario: Valid Macro

- **WHEN** a profile holds a macro with a `Tap` of key A, a `Wait` of 100 ms and a `Tap` of key B
- **THEN** `ojd profile validate` accepts the profile

#### Scenario: Step Destinations

- **WHEN** a step destination is a keyboard key, pointer button, virtual gamepad button or D-pad direction, system key, or typed text
- **THEN** `ojd profile validate` accepts it, and rejects a continuous destination, a macro and a profile control action

#### Scenario: Macro Inside a Macro

- **WHEN** a step of a macro has a `Macro` destination
- **THEN** `ojd profile validate` rejects the profile and names the step path

#### Scenario: Unknown Macro

- **WHEN** a binding has a `Macro` destination whose id is not in `macros`
- **THEN** `ojd profile validate` rejects the profile and names the macro id

### Requirement: REQ-28 Macro Timing and Order

A running macro MUST send its steps in order, and a step MUST NOT start before the earlier `Wait` and `Chord` hold times have elapsed on the monotonic clock. A `Chord` step MUST press its destinations, hold them, then release them in reverse order. A numeric `repeat` MUST run the step list that many times. `WhileHeld` MUST run it again until the source is released. A pass MUST start at least 1 ms after the previous pass started.

#### Scenario: Ordered Steps with Waits

- **WHEN** a macro of `Tap` A, `Wait` 100 ms, `Tap` B runs
- **THEN** key A goes down and up, key B goes down no earlier than 100 ms after key A went up, and key B goes up

#### Scenario: Repeat Count

- **WHEN** a macro with `repeat` 3 runs to its end
- **THEN** its step list ran exactly three times and every output it pressed is released

#### Scenario: Retrigger with Ignore

- **WHEN** the source is pressed again while the macro runs and `whileRunning` is `Ignore`
- **THEN** the running pass continues and no second pass starts

#### Scenario: Retrigger with Restart

- **WHEN** the source is pressed again while the macro runs and `whileRunning` is `Restart`
- **THEN** the running pass stops with every output released, and a new pass starts

### Requirement: REQ-29 Interrupt and Cleanup

A macro MUST stop and release every output it holds when `interruptOnRelease` is true and the source is released, and on profile change or deactivation, a pause action (REQ-40), controller disconnect, loss of the permission its outputs need, and service shutdown. A stopped macro MUST NOT start another pass. No stop path MUST leave a key, button or modifier down.

#### Scenario: Interrupt on Release

- **WHEN** a macro with `interruptOnRelease` true holds key A during a `Chord` step and the user releases the source
- **THEN** key A is released and no later step runs

#### Scenario: Controller Disconnect

- **WHEN** the controller disconnects while a macro with `repeat` `WhileHeld` runs
- **THEN** the macro stops and every output it held is released

### Requirement: REQ-30 Runaway Limits Are Validated, Not Applied Silently

OJD MUST reject at load a macro whose worst-case run time exceeds its limit, and MUST NOT cut a running macro short for any reason other than REQ-29. The run time of a pass is the sum of its `Wait` times and `Chord` hold times. The limits are one pass at most 30 seconds, and a numeric `repeat` times one pass at most 5 minutes.

#### Scenario: Run Time Over the Limit

- **WHEN** a macro has 8 `Wait` steps of 5000 ms each
- **THEN** `ojd profile validate` rejects the profile with the invalid-profile error that names the macro and the one-pass limit

### Requirement: REQ-31 Macro Surfaces

The profile editor MUST list, add, edit, reorder and remove macros and steps, and MUST offer a macro as a destination. `ojd binding set` MUST accept `macro:NAME` as a target, and the `ojd macro` group MUST list, show, set and remove the macros of a profile. Every user-facing string MUST be a localization key in all 22 bundles.

#### Scenario: Assign a Macro in the App

- **WHEN** the user picks Macro as the destination of an assignment and selects a macro
- **THEN** the assignment saves with a `Macro` destination for that macro

#### Scenario: Assign a Macro on the Command Line

- **WHEN** the user runs `ojd binding set PROFILE button:south macro:Combo`
- **THEN** the binding is saved, or the command fails with an error that names the missing macro
