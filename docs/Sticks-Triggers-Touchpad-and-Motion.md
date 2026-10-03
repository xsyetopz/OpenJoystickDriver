# Sticks, triggers, touchpad, and motion

Analog settings change how a stick, a trigger, a touch surface, or a motion sensor produces output.

## Contents

- [Before you begin](#before-you-begin)
- [Set a stick mode](#set-a-stick-mode)
- [Set trigger stages](#set-trigger-stages)
- [Set touch mapping](#set-touch-mapping)
- [Set motion tuning and gyro output](#set-motion-tuning-and-gyro-output)
- [Pair two Joy-Con controllers](#pair-two-joy-con-controllers)
- [Set the lighting color](#set-the-lighting-color)
- [Further reading](#further-reading)

## Before you begin

- Create a profile. For more information, see [Creating a profile](Remapping-Profiles.md#creating-a-profile).
- Open the **Controller** section of the profile. Each group in this section has an **Adjust** button.
- If a group shows **Not supported by this controller or protocol.**, the controller cannot provide that input.
- Stick modes that move the pointer or scroll need Accessibility access. For more information, see [Permissions](Permissions-and-Security.md).

A profile can have one stick mapping for each stick, one trigger mapping for each trigger, and one touch mapping for each surface.

## Set a stick mode

1. In the **Controller** section, click **Adjust** in the **Stick modes** group.
1. Select **Left stick** or **Right stick**.
1. Select **Enable pointer output**.
1. Select a **Stick mode**.
1. Change the settings for that mode.
1. Click **Save**.

| Stick mode | Result | Main settings |
| --- | --- | --- |
| **Aim** | Stick deflection turns the pointer at a steady speed. This is the default. | **Aim speed (degrees/s)**, 0 to 10000. The default is 360. |
| **Flick and rotate** | A quick flick turns the pointer by the stick angle. Then you can rotate the stick to turn further. | **Flick duration (ms)**, **Flick engagement threshold**, **Flick release hysteresis** |
| **Flick only** | Flicks work and rotation is ignored. | Same as **Flick and rotate** |
| **Rotate only** | Rotation works and flicks are ignored. | **Pointer points per degree** |
| **Pointer area** | The pointer moves to an offset that follows the stick. | **Pointer radius (points)**, 1 to 10000. The default is 128. |
| **Pointer ring** | The pointer follows the stick on a ring. | **Pointer radius (points)** |
| **Scroll wheel** | The stick rotation scrolls. | **Scroll axis**, **Rotation per scroll line (degrees)** |
| **Steering wheel** | The stick rotation drives a virtual steering axis. | **Virtual steering axis**, **Rotation at full steering (degrees)**, **Steering return speed (degrees/s)** |

The descriptions come from the code names and comments. Hardware behavior is not verified.

These settings apply to every mode:

- **Inner deadzone** and **Outer deadzone**, each 0 to 0.95. Their sum must be less than 1. The defaults are 0.1 and 0.
- **Response exponent**, 0.1 to 10. The default is 1.
- **Invert horizontal axis** and **Invert vertical axis**.
- **Keep physical stick passthrough**. This keeps the physical stick axes in the passthrough output.
- **Positive rotation**: **Clockwise** or **Counterclockwise**.

To change these settings with the command line, run `ojd profile edit PROFILE` and change `stickMappings` in the profile file. For the file format, see [Profile file reference](Profile-File-Reference.md). The stick modes are `aim`, `flick`, `flick_only`, `rotate_only`, `pointer_area`, `pointer_ring`, `scroll_wheel`, `steering`, and `none`. If a mapping is invalid while the profile runs, OJD sends neutral output.

## Set trigger stages

A dual-stage trigger has a soft stage and a full stage. You can assign each stage to a different destination.

1. In the **Controller** section, click **Adjust** in the **Trigger stages** group.
1. Select **Left trigger** or **Right trigger**.
1. Select **Enable dual-stage trigger**.
1. Select a **Stage interaction**.
1. Set the thresholds and **Release hysteresis**.
1. Click **Save**.
1. In the **Assignments** section, assign the `trigger:SIDE:soft` and `trigger:SIDE:full` controls.

| Stage interaction | CLI value |
| --- | --- |
| **Soft and full together** | `simultaneous` |
| **Full replaces soft** | `exclusive` |
| **Prefer quick full** | `prefer_full` |
| **Prefer quick full; combine late** | `prefer_full_combined` |
| **Responsive soft; prefer quick full** | `responsive_prefer_full` |
| **Responsive soft; combine late** | `responsive_prefer_full_combined` |

The soft threshold range is 0.01 to 0.95 (default 0.1). The full threshold range is 0.05 to 1 (default 0.95). The soft threshold must be less than the full threshold. The **Quick-pull window (ms)** range is 1 to 1000 (default 150). **Keep analog trigger passthrough** keeps the analog trigger in the passthrough output.

The command line options start with `--trigger-`, for example `--trigger-source left --trigger-mode prefer_full`.

## Set touch mapping

1. In the **Controller** section, click **Adjust** in the **Touch mappings** group.
1. Select the **Surface**: **Primary surface**, **Left surface**, or **Right surface**.
1. Select **Enable continuous touch output**.
1. Select a **Touch mode**: **Pointer**, **Left stick**, or **Right stick**.
1. Set the sensitivity, radius, or deadzone.
1. Click **Save**.

**Pointer points per surface** ranges from 1 to 5000 (default 1000). **Full stick radius (surface fraction)** ranges from 0.01 to 1 (default 0.25). **Stick deadzone** ranges from 0 to 0.95 (default 0.1).

You can also use touch contact, touch grid, and touch swipe as assignment sources. A grid has 1 to 16 columns and rows. A swipe has a minimum distance from 0.01 to 1 (default 0.2). For the source syntax, see [Assigning buttons and actions](Bindings-and-Actions.md#assigning-buttons-and-actions).

The command line options start with `--touch-`, for example `--touch-surface primary --touch-mode pointer`.

## Set motion tuning and gyro output

1. In the **Controller** section, click **Adjust** in the **Motion tuning** group.
1. Select the **Coordinate space**.
1. Set the sensitivity and other values.
1. Click **Save**. To go back to the profile values in a layer, click **Use profile tuning**.

Motion tuning has these values. The ranges come from the profile validation.

| Setting | Range | Default |
| --- | --- | --- |
| Space | `local`, `player`, `world` | `player` |
| Pitch and yaw sensitivity | 0 to 100 | 1 |
| Smoothing half-time (ms) | 0 to 1000 | 0 |
| Threshold (degrees per second) | 0 to 1000 | 0 |
| Automatic bias | On or off | On |

To change these settings with the command line, run `ojd profile edit PROFILE` and change `motionTuning` in the profile file.

**Gyro output** sends motion to the mouse pointer, the left stick, or the right stick. The modes are `disabled`, `mouse`, `left_stick`, and `right_stick`. The activation is **Always active**, **While held**, **While released**, or **Toggle on press**. Any activation other than **Always active** needs an **Activation control**. The default is disabled. To change it with the command line, run `ojd profile edit PROFILE` and change `gyroOutput` in the profile file.

A gyro trackball keeps motion going after you hold a control. **Velocity halvings per second** ranges from 0 to 1000. Zero keeps a constant speed.

Motion sources need a controller with motion sensors. Some controllers provide none.

## Pair two Joy-Con controllers

A paired Joy-Con profile combines a left and a right Joy-Con. The profile must target the Nintendo left Joy-Con model `057E:2006`.

1. Create a profile. In **Profile details**, select **Paired Joy-Con profile**.
1. Select the **Pair gyro source**: **Disabled**, **Left Joy-Con**, or **Right Joy-Con**.
1. Connect both Joy-Con controllers.
1. Click **Pair connected Joy-Cons...**.
1. When the label **Pair active** appears, the pair works. Click **Unpair** to end it.

A paired Joy-Con profile has no **Set active** button. The gyro setting works only after OJD pairs two exact Joy-Con controllers. The command line equivalents are `ojd controller pair LEFT RIGHT --profile PROFILE` and `ojd controller unpair PAIR`. Hardware behavior of Joy-Con pairing is not verified.

## Set the lighting color

In the **Controller** section, the **Lighting** editor sets a color. Select **Use controller default** to clear it. Only controllers with lighting support this setting. For more information, see [Rumble and lighting](Playing-Games.md).

## Further reading

- [Bindings and actions](Bindings-and-Actions.md)
- [Testing a controller](Testing-a-Controller.md)
