# About profiles

A profile is a saved set of remapping rules for one controller model.

Use this page to learn what a profile contains, how OpenJoystickDriver (OJD) picks the active profile, and what output policy means.

## What a profile contains

Each profile has a name, a controller model, and an application scope. The controller model is a vendor ID and product ID pair. For more information, see [Finding your controller ID](../connecting-controllers/finding-your-controller-id.md).

A profile can also contain these items:

- Assignments that map one control to one destination
- Chords, sequences, and layers
- Stick, trigger, touch, and motion settings
- An output policy
- A lighting color

A profile applies to every connected controller of its model.

## Scope

The scope decides when a profile is eligible to work.

- **All applications** (global): The profile works in every app.
- **One application**: The profile works only while one app is in front. You identify the app with its bundle identifier, for example `com.apple.Safari`.

## The active profile

A profile does nothing until you activate it. One controller model can have several active profiles, one for each application scope.

OJD picks the profile for a controller in this order:

1. The most recently activated profile whose application scope matches the front app.
1. The most recently activated global profile.
1. The most recently activated profile for the model, even if its scope is an app that is not in front.

If no profile is active, OJD passes the controller through to the virtual controller. An app-scoped profile picked by rule 3 does not work until its app is in front.

OJD reads the front app when a controller connects, and when you activate, deactivate, or edit a profile. Whether OJD re-evaluates the choice at the instant you switch apps is not verified.

> [!WARNING]
> Do not activate a second global profile for a model that already has one. Two active global profiles for one model crash the app at every launch. For more information, see [Known issues](../troubleshooting/known-issues.md).

## Output policy

The output policy decides how a profile sends its results. It has two settings.

| Setting | Values | Meaning |
| --- | --- | --- |
| Virtual gamepad | Disabled, Mapped controls only, Include unmapped controls | Whether OJD publishes a virtual controller for this profile |
| Require exclusive physical input | Off, On | Whether OJD takes exclusive ownership of the physical input |

- **Disabled**: OJD sends keyboard and pointer events only. There is no virtual controller output.
- **Mapped controls only**: OJD sends only the destinations that you assigned.
- **Include unmapped controls**: OJD also forwards controls that no assignment uses.

Virtual gamepad output needs exclusive physical input. A profile that you create in the app starts with **Include unmapped controls** and no assignments.

A profile that sends keyboard or pointer events needs Accessibility access. For more information, see [Permissions](../permissions-and-security/permissions.md).

## Further reading

- [Creating a profile](creating-a-profile.md)
- [Profile file reference](profile-file-reference.md)
- [How games see your controller](../playing-games/how-games-see-your-controller.md)
