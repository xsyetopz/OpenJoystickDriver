# Start: control the Mac with a controller

Make controller buttons press keys, click the mouse, move the pointer, or scroll.

## Before you begin

Install OJD and connect the controller. See [Start: play a game with a controller](Start-Play-a-Game.md). Keyboard and pointer output needs **Accessibility** access: click **Permission Missing: Accessibility** in the menu-bar menu, or run `ojd permission request input-inject`.

## Steps in the app

1. Open the **Profiles** area and click **New profile**.
2. In the **New profile** sheet, enter a name, select the controller in the **Controller** list, and select the application scope. Click **Create**.
3. Select the profile and open the **Assignments** section. Click **Add assignment**.
4. In the **Press a controller control** sheet, click **Listen for control** and press a button on the controller.
5. Select a **Destination**. For a key, click **Capture key** and press the key. Click **Add assignment**.
6. Click **Save**, then click **Set active**.

## Steps in Terminal

```shell
ojd profile create "My controller" --controller 045E:02FD
ojd binding set "My controller" button:south key:space
ojd profile activate "My controller"
```

Replace `045E:02FD` with the VID:PID of your controller, which `ojd controller list` shows. `ojd binding set` also takes `mouse:BUTTON`, `move:x|y`, and `scroll:x|y` as targets. `ojd binding list "My controller"` lists the assignments.

## Further reading

- [Remapping profiles](Remapping-Profiles.md#creating-a-profile)
- [Bindings and actions](Bindings-and-Actions.md#add-an-assignment-in-the-app)
- [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md)
- [Permissions and security](Permissions-and-Security.md#permissions)
