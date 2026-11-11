# Sticks, Triggers, Touchpad, and Motion

Analog settings change how a stick, a trigger, a touch surface, or a motion sensor produces output.

## Contents

- [Before You Begin](#before-you-begin)
- [Set a Stick Mode](#set-a-stick-mode)
- [Set Trigger Stages](#set-trigger-stages)
- [Set Touch Mapping](#set-touch-mapping)
- [Set Regions](#set-regions)
- [Set Pointer Speed](#set-pointer-speed)
- [Set Motion Tuning and Gyro Output](#set-motion-tuning-and-gyro-output)
- [Create a Gyro to Stick Profile](#create-a-gyro-to-stick-profile)
- [Pair Two Joy-Con Controllers](#pair-two-joy-con-controllers)
- [Set the Lighting Color](#set-the-lighting-color)
- [Further Reading](#further-reading)

## Before You Begin

- Create a profile. For more information, see [Creating a profile](Remapping-Profiles.md#creating-a-profile).
- Open the **Controller** section of the profile. Each group in this section has an **Adjust** button.
- If a group shows **Not supported by this controller or protocol.**, the controller cannot provide that input.
- Stick modes that move the pointer or scroll need Accessibility access. For more information, see [Permissions](Permissions-and-Security.md).

A profile can have one stick mapping for each stick, one trigger mapping for each trigger, and one touch mapping for each surface.

## Set a Stick Mode

1. In the **Controller** section, click **Adjust** in the **Stick modes** group.
2. Select **Left stick** or **Right stick**.
3. Select **Enable pointer output**.
4. Select a **Stick mode**.
5. Change the settings for that mode.
6. Click **Save**.

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

To change these settings with the command line, run `ojd profile edit PROFILE` and change `stickMappings` in the profile file. For the file format, see [Profile file reference](Profile-File-Reference.md). The stick modes are `Aim`, `Flick`, `FlickOnly`, `RotateOnly`, `PointerArea`, `PointerRing`, `ScrollWheel`, and `Steering`. If a mapping is invalid while the profile runs, OJD sends neutral output.

## Set Trigger Stages

A dual-stage trigger has a soft stage and a full stage. You can assign each stage to a different destination.

1. In the **Controller** section, click **Adjust** in the **Trigger stages** group.
2. Select **Left trigger** or **Right trigger**.
3. Select **Enable dual-stage trigger**.
4. Select a **Stage interaction**.
5. Set the thresholds and **Release hysteresis**.
6. Click **Save**.
7. In the **Assignments** section, assign the `trigger:SIDE:soft` and `trigger:SIDE:full` controls.

| Stage interaction | Profile value |
| --- | --- |
| **Soft and full together** | `Simultaneous` |
| **Full replaces soft** | `Exclusive` |
| **Prefer quick full** | `PreferFull` |
| **Prefer quick full; combine late** | `PreferFullCombined` |
| **Responsive soft; prefer quick full** | `ResponsivePreferFull` |
| **Responsive soft; combine late** | `ResponsivePreferFullCombined` |

The soft threshold range is 0.01 to 0.95 (default 0.1). The full threshold range is 0.05 to 1 (default 0.95). The soft threshold must be less than the full threshold. The **Quick-pull window (ms)** range is 1 to 1000 (default 150). **Keep analog trigger passthrough** keeps the analog trigger in the passthrough output.

On the command line, the settings are the `triggerMappings` entries of the profile. Change one with `ojd profile set`, for example `ojd profile set Racing triggerMappings.0.mode PreferFull`, or open the profile with `ojd profile edit`.

## Set Touch Mapping

1. In the **Controller** section, click **Adjust** in the **Touch mappings** group.
2. Select the **Surface**: **Primary surface**, **Left surface**, or **Right surface**.
3. Select **Enable continuous touch output**.
4. Select a **Touch mode**: **Pointer**, **Left stick**, or **Right stick**.
5. Set the sensitivity, radius, or deadzone.
6. Click **Save**.

**Pointer points per surface** ranges from 1 to 5000 (default 1000). **Full stick radius (surface fraction)** ranges from 0.01 to 1 (default 0.25). **Stick deadzone** ranges from 0 to 0.95 (default 0.1).

You can also use touch contact, touch grid, and touch swipe as assignment sources. A grid has 1 to 16 columns and rows. A swipe has a minimum distance from 0.01 to 1 (default 0.2). For the source syntax, see [Assigning buttons and actions](Bindings-and-Actions.md#assigning-buttons-and-actions).

On the command line, the settings are the `touchMappings` entries of the profile. Change one with `ojd profile set`, for example `ojd profile set Racing touchMappings.0.mode Pointer`, or open the profile with `ojd profile edit`.

## Set Regions

A region is a source that is on while a stick, a trigger, or a touch contact is in a part of its range. Assign it like a button. For example, a stick ring can hold Shift while you push the stick all the way.

1. In the **Controller** section, click **Adjust** in the **Regions** group.
2. Select a **Region type**: **Stick ring**, **Trigger band**, or **Touch area**.
3. Select the **Input**: the stick, the trigger, or the touch surface.
4. Set the numbers.
5. Select a **Destination**.
6. Click **Add assignment**, then **Save** in the profile editor.

While a controller is connected, the **Live position** drawing shows the region and a dot at the current position of the stick, trigger, or touch.

- **Stick ring**: **Inner radius** and **Outer radius** are fractions of the deflection after the stick dead zone, from 0 to 1, with the inner radius below the outer one. **Sector start** and **Sector end** are degrees clockwise from up, from 0 to 360. A sector may pass 0, as 315 to 45 does. Leave both empty for the whole ring. The live dot uses the dead zone of the stick mapping.
- **Trigger band**: **Band start** and **Band end** are pulls from 0 to 1. A trigger with bands cannot also have dual-stage trigger mappings.
- **Touch area**: the edges, **Width**, and **Height** are fractions of the surface. The area is on while any contact is in it.

Rings and sectors of one stick cannot overlap, and neither can bands of one trigger; OJD rejects the profile when you save it. A ring or band keeps its output while the input stays within the **Release hysteresis** (0 to 0.25, default 0.05) past an edge. When the input moves from one region into the next, OJD releases the first output before it presses the second.

On the command line, the sources are `stick-region:SIDE:INNER-OUTER[:FROM-TO]`, `trigger-band:SIDE:FROM-TO`, and `touch:SURFACE:area:X:Y:W:H`, for example `ojd binding set Racing stick-region:left:0.8-1 key:key-a`. For the other source syntax, see [Assigning buttons and actions](Bindings-and-Actions.md#region-sources).

## Set Pointer Speed

Pointer speed scales all pointer movement by the value of a trigger or a stick. It covers the stick pointer modes, the touch pointer, the gyro mouse, and the **Mouse movement** destination. Scrolling does not change.

1. In the **Controller** section, click **Adjust** in the **Pointer speed** group.
2. Select **Scale pointer speed**.
3. Select the **Driver**: **Trigger** or **Stick depth**, and the **Side**.
4. Set the **Scale at 0** and the **Scale at 1**, and select a **Curve**.
5. Click **Save**.

The scale is the **Scale at 0** when the driver is at rest and the **Scale at 1** when the trigger is fully pulled or the stick is at its rim. The curve shapes the values in between. Both scales range from 0 to 10. A scale of 0 stops the pointer. While the controller is connected, the editor shows the current scale.

Only a trigger or stick that the controller reports can be the driver.

With several controllers that each have a pointer speed, the scales of all of them apply to the one pointer.

On the command line, the setting is the `pointerSpeed` field of the profile. For example, to slow the pointer to a quarter while the left trigger is fully pulled:

```sh
ojd profile set Racing pointerSpeed '{"driver":{"type":"Trigger","side":"Left"},"minScale":1,"maxScale":0.25,"curve":"Linear"}'
```

## Set Motion Tuning and Gyro Output

1. In the **Controller** section, click **Adjust** in the **Motion tuning** group.
2. Select the **Coordinate space**.
3. Set the sensitivity and other values.
4. Click **Save**. To go back to the profile values in a layer, click **Use profile tuning**.

Motion tuning has these values. The ranges come from the profile validation.

| Setting | Range | Default |
| --- | --- | --- |
| Space | `Local`, `Player`, `World` | `Player` |
| Pitch and yaw sensitivity | 0 to 100 | 1 |
| Smoothing half-time (ms) | 0 to 1000 | 0 |
| Threshold (degrees per second) | 0 to 1000 | 0 |
| Automatic bias | On or off | On |

To change these settings with the command line, run `ojd profile edit PROFILE` and change `motionTuning` in the profile file.

**Gyro output** sends motion to the mouse pointer, the left stick, or the right stick. The modes are `Disabled`, `Mouse`, `LeftStick`, and `RightStick`. The activation is **Always active**, **While held**, **While released**, or **Toggle on press**. Any activation other than **Always active** needs an **Activation control**. The default is disabled. To change it with the command line, run `ojd profile edit PROFILE` and change `gyroOutput` in the profile file.

A gyro trackball keeps motion going after you hold a control. **Velocity halvings per second** ranges from 0 to 1000. Zero keeps a constant speed.

Motion sources need a controller with motion sensors. Some controllers provide none.

## Create a Gyro to Stick Profile

The **Gyro to stick** template makes a profile in which turning the controller moves a stick of the virtual gamepad, so a game that reads only sticks gets gyro aiming.

1. Click **New profile** and choose the controller.
2. Set **Template** to **Gyro to stick**, then choose the **Left stick** or the **Right stick**.
3. Click **Create**.

The profile turns the virtual gamepad on with every unmapped control passing through, and gyro output is always on. To make it active only while a control is held, set the activation in the motion sheet. With the command line, run `ojd profile create NAME --controller VVVV:PPPP --template gyro-stick`, and add `--stick left` or `--activation button:left-shoulder` to change the stick or to hold a control. If the controller model has no motion sensor, OpenJoystickDriver does not create the profile and says which model lacks one.

Hardware behavior: Not checked. The engine and its tests cover stick output, and [the hardware check](../docs/testing/gyro-stick.md) has not been run on a controller.

## Pair Two Joy-Con Controllers

A paired Joy-Con profile combines a left and a right Joy-Con. The profile must target the Nintendo left Joy-Con model `057E:2006`.

1. Create a profile. In **Profile details**, select **Paired Joy-Con profile**.
2. Select the **Pair gyro source**: **Disabled**, **Left Joy-Con**, or **Right Joy-Con**.
3. Connect both Joy-Con controllers.
4. Click **Pair connected Joy-Cons...**.
5. When the label **Pair active** appears, the pair works. Click **Unpair** to end it.

A paired Joy-Con profile has no **Set active** button. The gyro setting works only after OJD pairs two exact Joy-Con controllers. The command line equivalents are `ojd controller pair LEFT RIGHT --profile PROFILE` and `ojd controller unpair PAIR`. Hardware behavior of Joy-Con pairing is not verified.

## Set the Lighting Color

In the **Controller** section, the **Lighting** editor sets a color. Select **Use controller default** to clear it. Only controllers with lighting support this setting. For more information, see [Rumble and lighting](Playing-Games.md).

## Further Reading

- [Bindings and actions](Bindings-and-Actions.md)
- [Testing a controller](Testing-a-Controller.md)
