# Native Repository Tools

Use these probes only for intentional hardware tests.

Build the maintained `SDLGamepadProbe` without opening hardware:

```bash
./Scripts/ojd check tools
```

The build uses Apple Clang, the system `SDL3` package found through `pkg-config`, and the Foundation and GameController frameworks.

To test a connected controller for 10 seconds:

```bash
./Scripts/ojd diagnose sdl3 --seconds 10
```

Expected result: the probe lists SDL gamepad events and exits after 10 seconds. Add `--rumble` only when you intend to activate output on every SDL gamepad.
