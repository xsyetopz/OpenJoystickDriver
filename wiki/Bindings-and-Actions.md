# Bindings and Actions

Bindings connect controller controls to destinations, and combinations and layers let one [profile](Glossary.md#terms) do more with the same controls.

## Contents

- [Assigning Buttons and Actions](#assigning-buttons-and-actions)
- [Macros](#macros)
- [Switch Profiles, Set Layers, and Pause](#switch-profiles-set-layers-and-pause)
- [System Actions](#system-actions)
- [Spoken Phrases](#spoken-phrases)
- [Combinations, Sequences, and Layers](#combinations-sequences-and-layers)
- [Further Reading](#further-reading)

## Assigning Buttons and Actions

An assignment connects one controller control to one destination, such as a keyboard key, a mouse button, or a [virtual gamepad](Glossary.md#terms) button.

### Before You Begin

- Create a profile. For more information, see [Creating a profile](Remapping-Profiles.md#creating-a-profile).
- Connect the controller if you want to use **Listen for control**.
- Grant Accessibility access if the destination is a keyboard key or a pointer action. For more information, see [Permissions](Permissions-and-Security.md).

### Destinations

| Destination | Examples | Notes |
| --- | --- | --- |
| Keyboard | A key with optional Command, Control, Option, and Shift | Needs Accessibility access |
| Mouse button | Left, right, middle, back, forward | Needs Accessibility access |
| Pointer movement | Horizontal or vertical | Continuous; the axis sets the speed of the cursor |
| Pointer position | Horizontal or vertical | Continuous; the axis value from -1 to 1 places the cursor across the main display, and the other coordinate keeps its value; needs Accessibility access |
| Scroll | Horizontal or vertical | Continuous |
| Gamepad button, D-pad, or axis | A virtual gamepad control | Needs virtual gamepad output |
| Physical output | Rumble, player indicator, color, brightness, adaptive trigger | Only on controllers that support it |
| Macro | A macro of the profile | Discrete sources only; see [Macros](#macros) |
| Profile switch | The next or previous profile, or a named profile of the same controller model | Discrete sources only; fires on press; see [Switch profiles, set layers, and pause](#switch-profiles-set-layers-and-pause) |
| Layer set | Turn a layer of the profile on or off, or flip it | Discrete sources only; fires on press |
| Pause | Pause or resume the controller, or flip it | Discrete sources only; fires on press |
| System key | Play/pause, next or previous track, fast-forward, rewind, volume up or down, mute, display brightness, keyboard backlight | Discrete sources only; needs Accessibility access; see [System actions](#system-actions) |
| System action | Mission Control, Launchpad, Screenshot | Discrete sources only; fires on press; see [System actions](#system-actions) |
| Open application | An application by bundle identifier | Discrete sources only; fires on press; command line or profile file only |
| Open URL | A web or other non-file URL | Discrete sources only; fires on press; command line or profile file only |
| Run Shortcut | A shortcut of the Shortcuts app, by name | Discrete sources only; fires on press; command line or profile file only |
| Type text | A fixed string | Discrete sources only; fires on press; needs Accessibility access; command line or profile file only |
| Speak | A phrase the Mac says aloud | Discrete sources only; see [Spoken Phrases](#spoken-phrases) |
| MIDI note or control change | A note on a channel, or a controller number | Needs no access; see [MIDI output](#midi-output) |

A gamepad destination fails validation if the profile output policy has the virtual gamepad disabled. Some controls, such as paddles, grips, and function buttons, cannot be a virtual gamepad output. For the controls each virtual gamepad carries, see [What the virtual gamepad carries](Automating-OpenJoystickDriver.md#what-the-virtual-gamepad-carries). For more information, see [About profiles](Remapping-Profiles.md#about-profiles).

Each controller control can appear in only one assignment in a profile.

### Add an Assignment In the App

1. Select the profile and open the **Assignments** section.
2. Click **Add assignment**.
3. In the **Press a controller control** sheet, select a control in the **Controller control** list. Or click **Listen for control** and press the control on the controller.
4. Select a **Destination**.
5. If the destination is a key, click **Capture key** and press the key with any modifiers. Press <kbd>Escape</kbd> to cancel the capture.
6. Click **Add assignment**.
7. Click **Save**.

The section groups assignments as **Face buttons**, **Shoulders**, **D-pad**, **Sticks**, **Triggers**, **Stick clicks**, **Touch**, **Motion**, and **System controls**. To remove an assignment, use its **Remove assignment** button.

### Add an Assignment With the Command Line

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
TARGET: key:KEY[:mods=alt,control,meta,shift]
        mouse:BUTTON | move:x|y | position:x|y | scroll:x|y
        gamepad:button:NAME | gamepad:dpad:DIRECTION
        gamepad:axis:NAME
        physical:rumble:MOTOR:0...1
        physical:player:0...4
        physical:color:RED:GREEN:BLUE
        physical:brightness:0...1
        midi-note:CHANNEL:NOTE[:VELOCITY]
        midi-cc:CHANNEL:CONTROLLER
```

To remove an assignment, run `ojd binding clear PROFILE SOURCE`. To list the assignments, run `ojd binding list PROFILE`. For the options of `ojd binding set`, see [Command reference](Command-Reference.md).

### Set a Behavior

The behavior decides how a press turns into output.

1. Click **Behavior...** on the assignment row.
2. In the **Assignment behavior** sheet, select a behavior.
3. Click **Apply**, then click **Save**.

| Behavior | Result |
| --- | --- |
| **Hold** | The destination stays active while you hold the control. This is the default. |
| **Toggle** | Each press switches the destination on or off. |
| **Tap on press** | The destination taps once when you press the control. |
| **Tap on release** | The destination taps once when you release the control. |
| **Pulse** | The destination stays active for the **Pulse duration**. The default is 100 ms. |
| **Press only** | OJD sends only the press. |
| **Release only** | OJD sends only the release. |

The table describes each behavior by its name. Hardware results are not verified. The command line option is `--behavior hold|toggle|tap-on-press|tap-on-release|pulse|press|release`. Use `--pulse-ms 1...5000` with `pulse`.

### Turbo, Long Hold, and Multi-Tap

These options are in the **Assignment behavior** sheet. They work only when the behavior is **Hold**. Turbo cannot be combined with long hold or multi-tap.

- **Turbo** repeats the destination while you hold the control. Set the **Repeat rate** (1 to 60 Hz) and the **Duty cycle** (0.05 to 0.95). Optionally set a delay before the first repeat (0 to 2500 ms) and a cap on the number of repeats (1 to 500). Turbo works with keyboard, mouse button, gamepad button, and D-pad destinations.
- **Long hold** sends a second destination after you hold the control for the **Hold duration** (100 to 5000 ms).
- **Multi-tap** sends a second destination when you tap the control 2 to 5 times, each press within the **Tap window** (50 to 1000 ms) of the last release. Each tap count has its own destination, and counts are unique.

Long hold and multi-tap need a discrete source, such as a button, and a destination that is not continuous.

With multi-tap entries, the base destination waits for the longest tap window to see whether another tap follows, so it fires later than without them. `ojd binding list` shows this wait as `tap-delay`.

The command line options are `--turbo-rate`, `--turbo-duty`, `--turbo-delay MS`, `--turbo-max COUNT`, `--long-hold MS:TARGET`, and `--multi-tap COUNT:MS:TARGET`. `--turbo-delay` and `--turbo-max` need `--turbo-rate` and `--turbo-duty`. Repeat `--multi-tap` for more counts. For example, `--long-hold 500:key:key-b` and `--multi-tap 3:300:key:key-b`. The command line help lists these options for keyboard and mouse button destinations only. Whether the command line accepts them for gamepad destinations is not verified.

You can also add more actions to one assignment. In the behavior sheet, use **Add action**, **Move up**, **Move down**, and **Remove**. The command line option is `--actions-json`.

### Add a Note to an Assignment

The **Assignment behavior** sheet has a note field, labelled **Note (optional)**, of 1 to 200 characters. The note appears under the assignment in the list and does not change what the assignment does. Clear the field to remove the note. A profile file stores it as the binding's `remark`; for more information, see [Profile file reference](Profile-File-Reference.md).

### Macros

A macro is a named list of steps that runs when its source becomes active. A profile holds up to 16 macros of up to 32 steps. Hardware status: Not checked.

1. Open the **Macros** section and click **Add macro**.
2. Enter a **Macro name** (1 to 40 characters, unique in the profile).
3. Use **Add step** to add a step. Use the arrow buttons to reorder steps and the minus button to remove one. The steps are:
   - **Tap**: press and release a key or button at once.
   - **Press** and **Release**: hold a key or button down, then let it go.
   - **Chord**: press several keys or buttons together, hold them for the **Hold time**, then release them in reverse order. Use **Add key to chord** for more.
   - **Wait**: pause 0 to 5000 ms before the next step.
4. Set **Repeat** to **Fixed number of times** (1 to 500) or **While held**, which runs again until you release the control.
5. Set **When pressed again while running** to **Ignore** or **Restart**.
6. Turn on **Stop when released** to stop the macro and release everything it holds when you release the control.
7. Confirm the sheet, then click **Save**.

To run a macro, choose it as the **Destination** of an assignment. The destination list shows the macros of the profile for any source that is not a continuous axis. A step can be a keyboard key, a mouse button, a virtual gamepad button, or a D-pad direction. A step cannot be another macro. A macro that is the destination of an assignment cannot be removed until you change that assignment.

A macro stops and releases every key and button it holds when its source is released with **Stop when released** on, when the profile changes or stops, and when the controller disconnects. One pass takes at most 30 seconds, and a fixed repeat at most 5 minutes, counting the waits and chord hold times; OJD rejects a longer macro when it saves.

The command line is `ojd macro` and the target `macro:NAME` of `ojd binding set`. For more information, see [Command reference](Command-Reference.md#macro).

### Spoken Phrases

The **Speak** destination makes the Mac say a short text aloud when you press the control. Hardware status: Not checked.

1. Choose **Speak** as the **Destination** of an assignment.
2. Enter the **Text**, 1 to 128 characters.
3. Optionally enter a **Voice identifier**, such as `com.apple.voice.compact.en-US.Samantha`. With none, the Mac uses the system voice.

Pressing the control again while the phrase is still speaking stops it and says it again from the start, so repeated presses never queue phrases. Speech stops at once when the profile is paused or deactivated, or when the controller disconnects. Speech needs no Accessibility access. A macro step cannot speak.

OJD rejects an empty text, a text over 128 characters and an empty voice identifier when it loads a profile. It rejects a voice that this Mac does not have when you activate the profile.

The command line target is `speak:TEXT` of `ojd binding set`, with `--voice IDENTIFIER` for the voice:

```sh
ojd binding set Racing button:north speak:Reloading --voice com.apple.voice.compact.en-US.Samantha
```

### Tune an Analog Control

When you assign a stick axis or trigger axis, the row has an **Adjust...** button (needs the **Advanced** interface). It opens a sheet with these settings:

- Deadzone, 0 to 0.95. The default is 0.1.
- **Gain**, 0.1 to 10. The default is 1.
- **Invert axis**.
- **Response curve**: `linear`, `ease-in`, `ease-out`, or `smooth-step` on the command line.
- **Digital threshold**, 0.01 to 1. The default is 0.5. The threshold decides when an axis counts as pressed for a button destination.

The command line options are `--deadzone`, `--gain`, `--invert`, `--response-curve`, and `--digital-threshold`. An axis source needs these settings. A non-axis source cannot have them.

### Region Sources

A region source is on while a stick, trigger, or touch contact is inside a range, so every behavior, macro, layer, and combination works with it.

```text
SOURCE: stick-region:left|right:INNER-OUTER[:FROM-TO]
        trigger-band:left|right:FROM-TO
        touch:SURFACE:area:X:Y:W:H
```

`INNER-OUTER` are stick deflections from 0 to 1 after the dead zone, `FROM-TO` on a stick are degrees clockwise from up, `FROM-TO` on a trigger are pulls from 0 to 1, and the touch values are fractions of the surface. For example, `ojd binding set "My controller" stick-region:left:0.8-1 key:key-a` presses A while the left stick is pushed past 0.8. Regions of one stick and bands of one trigger must not overlap. To add one in the app, use **Regions** in the **Controller** section. For the fields and the live position view, see [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md#set-regions).

### Restore Or Clear Assignments

- To remove every assignment, select **Clear all inputs**.
- To return to pass-through, select **Restore Default Input** in the **Profile actions** menu.

## Switch Profiles, Set Layers, and Pause

Three destinations change what OJD does instead of sending input. Each fires when its source is pressed. Hardware status: Not checked.

- **Next profile** and **Previous profile** activate the neighbor of the active profile among the profiles for the same controller model and application scope. The order is the profile name without regard to case, then the profile identifier, and it wraps around. A profile switch to a named profile must name a profile for the same controller model. Otherwise OJD rejects the profile.
- **Turn layer on**, **Turn layer off**, and **Toggle layer** set a layer of the same profile.
- **Pause controller**, **Resume controller**, and **Toggle pause** pause the controller. A paused controller releases everything it holds, including running macros, drops its layers, and passes through unmapped. Only the pause assignment keeps working. A profile change or a disconnect ends the pause. While the pause lasts, the Controllers detail lists Remapping as Paused, the menu bar menu shows a disabled Paused row under the controller, and `ojd status` reports `paused`.

Each switch writes a line to the service log with the old and new profile names, and a failed switch writes its error there. To read the log, run `ojd log`.

To assign them with the command line, use these targets with `ojd binding set`:

```sh
ojd binding set Racing button:start profile:switch:next
ojd binding set Racing button:back profile:switch:PROFILE-ID
ojd binding set Racing button:west layer:Aim:toggle
ojd binding set Racing button:guide pause:toggle
```

The layer in `layer:NAME:MODE` is a layer of the profile, found by name without regard to case. The modes are `on`, `off`, and `toggle`.

## System Actions

These destinations make the Mac do something instead of sending a key or a button. Hardware status: Not checked.

- **System key** sends a media, volume, display brightness, or keyboard backlight key. It sends the key down when you press the control and the key up when you release it, so holding the control repeats the key as holding the key does. The names are `play-pause`, `next-track`, `previous-track`, `fast-forward`, `rewind`, `volume-up`, `volume-down`, `mute`, `brightness-up`, `brightness-down`, `keyboard-illumination-up`, and `keyboard-illumination-down`. It does not take turbo.
- **Mission Control** opens Mission Control.
- **Launchpad** opens Launchpad. On a macOS version that has no Launchpad, it opens the Apps app that replaces it.
- **Screenshot** opens the Screenshot app, which shows the capture toolbar.
- **Open application** opens an application by its bundle identifier, such as `com.apple.TextEdit`.
- **Open URL** opens a URL in its default application. A `file:` URL is rejected.
- **Run Shortcut** runs a shortcut of the Shortcuts app by name. A shortcut that asks for input waits for you. OJD does not wait for it to finish.
- **Type text** types a fixed string as keyboard events. While macOS has secure input on, such as in a password field, macOS may not deliver the keys, and OJD reports that secure input is on.

Each action uses one public macOS API. None of the new ones needs a permission in the Privacy & Security pane.

| Action | Public API | Permission | Source |
| --- | --- | --- | --- |
| Mission Control | `NSWorkspace.openApplication(at:configuration:)` on the Mission Control app | None | [openApplication(at:configuration:completionHandler:)](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)) |
| Launchpad | `NSWorkspace.urlForApplication(withBundleIdentifier:)` for `com.apple.launchpad.launcher`, then `com.apple.apps.launcher`, and `openApplication(at:configuration:)` | None | [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) |
| Screenshot | `NSWorkspace.urlForApplication(withBundleIdentifier:)` for `com.apple.screenshot.launcher`, and `openApplication(at:configuration:)` | None | [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) |
| Type text | `CGEvent(keyboardEventSource:virtualKey:keyDown:)`, `keyboardSetUnicodeString`, and `CGEvent.post(tap:)` | Accessibility (Post Event) | [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent) |

Apple's pages for `openApplication` state no permission for launching an app. The Launchpad, Screenshot, and bundle-identifier rows are read from the NSWorkspace API and the bundle identifiers on macOS 27.2, not stated by Apple's pages.

**Lock Screen** and **Show Desktop** are not actions: macOS has no public API for either. Lock Screen would need the private `SACLockScreenImmediate` or the retired `CGSession` tool, and a search of Apple's documentation finds no call to show the desktop. To get either, assign the keyboard shortcut that you set in System Settings, such as <kbd>Control</kbd>+<kbd>Command</kbd>+<kbd>Q</kbd>, to a keyboard destination.

All of them except System key act once when you press the control and do nothing on release. They take the behaviors **Hold**, **Tap on press**, **Tap on release**, and **Press**. **Toggle**, **Release**, and **Pulse** fail validation. A failed action writes its error to the Activity log and the service log, and the profile keeps working. To read the log, run `ojd log`.

To assign them with the command line, use these targets with `ojd binding set`:

```sh
ojd binding set Racing button:north system-key:volume-up
ojd binding set Racing button:west system:mission-control
ojd binding set Racing button:select system:launchpad
ojd binding set Racing button:guide system:screenshot
ojd binding set Racing button:east open-app:com.apple.TextEdit
ojd binding set Racing button:south open-url:https://example.com
ojd binding set Racing button:start shortcut:"Dim Lights"
ojd binding set Racing button:back text:hello
```

The app lists the system keys, Mission Control, Launchpad, Screenshot, and one entry each for Open application, Open URL, Run Shortcut, and Type text in the destination pickers. Choosing one of the four shows a text field for its application identifier, URL, Shortcut name, or text.

OJD does not offer Show Desktop, App Exposé, Launchpad, or a display brightness setting that needs private macOS interfaces: DisplayServices, CoreDock, SkyLight, CGS, and MediaRemote. To get one of them, set a keyboard shortcut for it in **System Settings**, then assign a **Keyboard** destination with that shortcut.

## MIDI Output

A **MIDI note** or **MIDI control change** destination sends MIDI to music apps. While an active profile uses one, OJD publishes a MIDI source named `OpenJoystickDriver`; pick it as the input of the app. OJD removes the source after the last note-off, once no active profile uses MIDI. No access permission is needed. If the system refuses to create the source, the assignment fails with error `E3032` and nothing is sent.

| Destination | File type | Sends |
| --- | --- | --- |
| MIDI note | `MidiNote` with `channel` 1 to 16, `note` 0 to 127, and `velocity` 1 to 127 | Note-on when the control is pressed and note-off when it is released |
| MIDI control change | `MidiControlChange` with `channel` 1 to 16 and `controller` 0 to 127 | A button sends 127 when pressed and 0 when released. A trigger sends its position as 0 to 127. A stick axis sends its position with the center at 64. A value is sent only when it changes. |

With the command line, `midi-note:CHANNEL:NOTE` sends velocity 127, and `midi-note:CHANNEL:NOTE:VELOCITY` sets it. For example, `ojd binding set PROFILE button:south midi-note:1:60:100` sends `90 3C 64` on press and `80 3C 00` on release. `midi-cc:CHANNEL:CONTROLLER` takes a control change, and only it fits an axis or trigger source. A macro step cannot send MIDI. Deactivating the profile releases every held note before the source goes away. The app's destination list offers MIDI note 60 on channel 1 and controller 1 on channel 1; edit the profile file for other numbers. For the file format, see [Profile file reference](Profile-File-Reference.md).

## Combinations, Sequences, and Layers

Chords, sequences, and layers let one profile do more with the same controls.

### Concepts

- A chord is a set of two or more controls that you press together. It sends one destination.
- A sequence is a list of two or more controls that you press in order. It sends one destination. A sequence is a trigger. It does not send several outputs.
- A layer is a second set of assignments. It is active while you hold an activator control, or after you press it once.

Chords and sequences cannot use axis controls or continuous destinations such as pointer movement. A chord source set must be unique in the profile.

### Before You Begin

Create a profile and open it. For more information, see [Creating a profile](Remapping-Profiles.md#creating-a-profile).

### Add a Chord

1. Open the **Combinations** section.
2. In **Chords**, click **Add chord**.
3. Select the first control in **Control 1**.
4. Click **Add control** and select at least one more control.
5. Select a **Chord mode**: **Modifier** or **Simultaneous**.
6. Set the **Press window**. The default is 50 ms and the range is 1 to 1000 ms.
7. Select a **Destination**.
8. Confirm the sheet, then click **Save**.

The sheet shows this hint: "The destination fires while all selected controls are pressed."

To add or delete a chord with the command line, run `ojd profile edit PROFILE`, then add or change the entry in `chords` in the profile file. For the file format, see [Profile file reference](Profile-File-Reference.md).

### Add a Sequence

1. Open the **Combinations** section.
2. In **Sequences**, click **Add sequence**.
3. Add at least two controls in the order that you press them.
4. Set the **Completion window**. The range is 200 to 10000 ms.
5. Select a **Destination**.
6. Confirm the sheet, then click **Save**.

To add or delete a sequence with the command line, run `ojd profile edit PROFILE`, then add or change the entry in `sequences` in the profile file. For the file format, see [Profile file reference](Profile-File-Reference.md).

### Add a Layer

1. Open the **Layers** section.
2. Click **Add layer**.
3. Enter a **Layer name** (1 to 40 characters).
4. Select the **Activator**. The activator is a button or a D-pad direction.
5. Select the **Activation**: **Hold** or **Toggle**.
6. Confirm the sheet, then click **Save**.
7. In the layer, click **Add assignment** to add assignments that work while the layer is active.

**Hold** keeps the layer active while you hold the activator. **Toggle** switches the layer on or off each time you press the activator. The activator cannot also be an assignment in the profile.

To add, change, or delete a layer with the command line, run `ojd profile edit PROFILE`, then add or change the entry in `layers` in the profile file. For the file format, see [Profile file reference](Profile-File-Reference.md). A layer can also have its own **Motion tuning**. For more information, see [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md).

## Further Reading

- [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md)
- [Command reference](Command-Reference.md)
