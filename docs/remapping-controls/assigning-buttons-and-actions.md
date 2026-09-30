# Assigning buttons and actions

An assignment connects one controller control to one destination, such as a keyboard key, a mouse button, or a virtual gamepad button.

## Before you begin

- Create a profile. For more information, see [Creating a profile](creating-a-profile.md).
- Connect the controller if you want to use **Listen for control**.
- Grant Accessibility access if the destination is a keyboard key or a pointer action. For more information, see [Permissions](../permissions-and-security/permissions.md).

## Destinations

| Destination | Examples | Notes |
| --- | --- | --- |
| Keyboard | A key with optional Command, Control, Option, and Shift | Needs Accessibility access |
| Mouse button | Left, right, middle, back, forward | Needs Accessibility access |
| Pointer movement | Horizontal or vertical | Continuous |
| Scroll | Horizontal or vertical | Continuous |
| Gamepad button, D-pad, or axis | A virtual controller control | Needs virtual gamepad output |
| Physical output | Rumble, player indicator, color, brightness, adaptive trigger | Only on controllers that support it |

A gamepad destination fails validation if the profile output policy has the virtual gamepad disabled. Some controls, such as paddles, grips, and function buttons, cannot be a virtual controller output. For more information, see [About profiles](about-profiles.md).

Each controller control can appear in only one assignment in a profile.

## Add an assignment in the app

1. Select the profile and open the **Assignments** section.
1. Click **Add assignment**.
1. In the **Press a controller control** sheet, select a control in the **Controller control** list. Or click **Listen for control** and press the control on the controller.
1. Select a **Destination**.
1. If the destination is a key, click **Capture key** and press the key with any modifiers. Press <kbd>Escape</kbd> to cancel the capture.
1. Click **Add assignment**.
1. Click **Save**.

The section groups assignments as **Face buttons**, **Shoulders**, **D-pad**, **Sticks**, **Triggers**, **Stick clicks**, **Touch**, **Motion**, and **System controls**. To remove an assignment, use its **Remove assignment** button.

## Add an assignment with the command line

```shell
ojd binding set "My controller" button:south key:space
```

A control has one assignment, so this command replaces the control's assignment. The `SOURCE` and `TARGET` values use this syntax:

```text
SOURCE: button:NAME | dpad:DIRECTION
        axis:NAME[:negative|positive]
        trigger:left|right:soft|full
        touch:SURFACE:contact
        touch:SURFACE:grid:COLUMNS:ROWS:COLUMN:ROW
        touch:SURFACE:swipe:DIRECTION:MIN-DISTANCE
        motion:lean:left|right
TARGET: key:KEY[:mods=command,control,option,shift]
        mouse:BUTTON | move:x|y | scroll:x|y
        gamepad:button:NAME | gamepad:dpad:DIRECTION
        gamepad:axis:NAME
        physical:rumble:MOTOR:0...1
        physical:player:0...4
        physical:color:RED:GREEN:BLUE
        physical:brightness:0...1
```

To remove an assignment, run `ojd binding clear PROFILE SOURCE`. To list the assignments, run `ojd binding list PROFILE`. For the options of `ojd binding set`, see [Command reference](../command-line/command-reference.md#binding).

## Set a behavior

The behavior decides how a press turns into output.

1. Click **Behavior...** on the assignment row.
1. In the **Assignment behavior** sheet, select a behavior.
1. Click **Apply**, then click **Save**.

| Behavior | Result |
| --- | --- |
| **Hold** | The destination stays active while you hold the control. This is the default. |
| **Toggle** | Each press switches the destination on or off. |
| **Tap on press** | The destination taps once when you press the control. |
| **Tap on release** | The destination taps once when you release the control. |
| **Pulse** | The destination stays active for the **Pulse duration**. The default is 100 ms. |
| **Press only** | OJD sends only the press. |
| **Release only** | OJD sends only the release. |

The table describes each behavior by its name. Hardware results are not verified. The command line option is `--behavior hold|toggle|tap_on_press|tap_on_release|pulse|press|release`. Use `--pulse-ms 1...5000` with `pulse`.

## Turbo, long hold, and double tap

These options are in the **Assignment behavior** sheet. They work only when the behavior is **Hold**. Turbo cannot be combined with long hold or double tap.

- **Turbo** repeats the destination while you hold the control. Set the **Repeat rate** (1 to 60 Hz) and the **Duty cycle** (0.05 to 0.95). Turbo works with keyboard, mouse button, gamepad button, and D-pad destinations.
- **Long hold** sends a second destination after you hold the control for the **Hold duration** (100 to 5000 ms).
- **Double tap** sends a second destination when you tap twice within the **Tap window** (50 to 1000 ms).

Long hold and double tap need a discrete source, such as a button, and a destination that is not continuous.

The command line options are `--turbo-rate`, `--turbo-duty`, `--long-hold MS:TARGET`, and `--double-tap MS:TARGET`. For example, `--long-hold 500:key:b`. The command line help lists these options for keyboard and mouse button destinations only. Whether the command line accepts them for gamepad destinations is not verified.

You can also add more actions to one assignment. In the behavior sheet, use **Add action**, **Move up**, **Move down**, and **Remove**. The command line option is `--actions-json`.

## Tune an analog control

When you assign a stick axis or trigger axis, the row has an **Adjust...** button. It opens a sheet with these settings:

- Deadzone, 0 to 0.95. The default is 0.1.
- **Gain**, 0.1 to 10. The default is 1.
- **Invert axis**.
- **Response curve**: `linear`, `ease_in`, `ease_out`, or `smooth_step`.
- **Digital threshold**, 0.01 to 1. The default is 0.5. The threshold decides when an axis counts as pressed for a button destination.

The command line options are `--deadzone`, `--gain`, `--invert`, `--response-curve`, and `--digital-threshold`. An axis source needs these settings. A non-axis source cannot have them.

## Restore or clear assignments

- To remove every assignment, select **Clear all inputs**.
- To return to pass-through, select **Restore default input** in the **Profile actions** menu.

## Further reading

- [Combinations, sequences, and layers](combinations-sequences-and-layers.md)
- [Sticks, triggers, touchpad, and motion](sticks-triggers-touchpad-and-motion.md)
- [Command reference](../command-line/command-reference.md)
