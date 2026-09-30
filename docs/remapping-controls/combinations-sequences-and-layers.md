# Combinations, sequences, and layers

Chords, sequences, and layers let one profile do more with the same controls.

## Concepts

- A chord is a set of two or more controls that you press together. It sends one destination.
- A sequence is a list of two or more controls that you press in order. It sends one destination. A sequence is a trigger. It does not send several outputs.
- A layer is a second set of assignments. It is active while you hold an activator control, or after you press it once.

Chords and sequences cannot use axis controls or continuous destinations such as pointer movement. A chord source set must be unique in the profile.

## Before you begin

Create a profile and open it. For more information, see [Creating a profile](creating-a-profile.md).

## Add a chord

1. Open the **Combinations** section.
1. In **Chords**, click **Add chord**.
1. Select the first control in **Control 1**.
1. Click **Add control** and select at least one more control.
1. Select a **Chord mode**: **Modifier** or **Simultaneous**.
1. Set the **Press window**. The default is 50 ms and the range is 1 to 1000 ms.
1. Select a **Destination**.
1. Confirm the sheet, then click **Save**.

The sheet shows this hint: "The destination fires while all selected controls are pressed."

The command line equivalent is:

```shell
OpenJoystickDriver --headless map chord add "My controller" \
  --sources button:left_shoulder,button:right_shoulder \
  --target key:space --mode simultaneous --window-ms 50
```

To delete a chord, run `map chord delete PROFILE --id CHORD-ID`.

## Add a sequence

1. Open the **Combinations** section.
1. In **Sequences**, click **Add sequence**.
1. Add at least two controls in the order that you press them.
1. Set the **Completion window**. The range is 200 to 10000 ms.
1. Select a **Destination**.
1. Confirm the sheet, then click **Save**.

The command line equivalent is:

```shell
OpenJoystickDriver --headless map sequence add "My controller" \
  --sources button:south,button:east \
  --window 1000 --target key:return
```

To delete a sequence, run `map sequence delete PROFILE --id SEQUENCE-ID`.

## Add a layer

1. Open the **Layers** section.
1. Click **Add layer**.
1. Enter a **Layer name** (1 to 40 characters).
1. Select the **Activator**. The activator is a button or a D-pad direction.
1. Select the **Activation**: **Hold** or **Toggle**.
1. Confirm the sheet, then click **Save**.
1. In the layer, click **Add assignment** to add assignments that work while the layer is active.

**Hold** keeps the layer active while you hold the activator. **Toggle** switches the layer on or off each time you press the activator. The activator cannot also be an assignment in the profile.

The command line equivalents are:

```shell
OpenJoystickDriver --headless map layer create "My controller" \
  --name Shift --activator button:left_shoulder --mode hold
OpenJoystickDriver --headless map layer list "My controller"
OpenJoystickDriver --headless map layer bind "My controller" \
  --layer LAYER-ID --source button:south --target key:a
```

Use `map layer unbind` to remove a layer assignment and `map layer delete PROFILE --id LAYER-ID` to delete a layer. A layer can also have its own **Motion tuning**. For more information, see [Sticks, triggers, touchpad, and motion](sticks-triggers-touchpad-and-motion.md).

## Further reading

- [Assigning buttons and actions](assigning-buttons-and-actions.md)
- [Command reference](../command-line/command-reference.md)
