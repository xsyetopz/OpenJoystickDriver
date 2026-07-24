# Compatibility source notes

These projects informed OJD architecture. They are evidence for design choices, not dependencies or support claims. Snapshots of the relevant SDL discussions live under `docs/external/sdl/`.

## Sources

### InputFusion

Separates physical input, mapping, and virtual output. OJD follows the same boundary with `DeviceManager`, protocol parsers, normalized `ControllerEvent` values, and output dispatchers.

### Xb2XInput

Shows why connection lifecycle, guide-button handling, and controller slots belong to the transport layer. OJD keeps those concerns out of generic mapping code.

### xinput-gui

Provides a useful model for explicit device and control-plane diagnostics. OJD exposes typed state through the CLI and application runtime instead of hiding application-service decisions.

### DualShock4-emulator

Keeps Sony report parsing separate from the virtual Xbox-facing surface. OJD uses protocol parsers for physical reports and compatibility profiles for consumer identity.

### Gopher360

Demonstrates that desktop keyboard or mouse translation is a separate product behavior. OJD does not synthesize desktop keyboard or mouse input. Its Accessibility request authorizes IOHIDUserDevice compatibility output.

### Joypad OS

Reinforces the difference between controller state, client routing, and output ownership. OJD uses one pipeline per physical controller and explicit output backends.

### Linux input drivers

`xpad.c`, `hid-playstation.c`, `hid-sony.c`, `hid-nintendo.c`, and `hid-steam.c` provide protocol and device evidence. Linux recognition does not prove macOS descriptors, endpoints, TCC behavior, or Apple GameController support.

### SDL

SDL mappings and HIDAPI code show how consumer identity affects naming, button order, and rumble. OJD keeps consumer mappings in compatibility profiles and diagnostic tools rather than embedding application quirks in physical parsers.

## Architecture decisions

1. A physical device has one input owner and one pipeline.
2. Parsers emit normalized state; they do not choose a consumer identity.
3. Compatibility profiles own virtual VID/PID, descriptors, mappings, and report formats.
4. Physical output capabilities come from the active protocol parser.
5. Unknown standard HID devices may use descriptor-driven input. Vendor protocols need records.
6. The CLI and application runtime use the same application-service and diagnostic services.
7. Duplicate physical and virtual devices are treated as an ownership bug, not a mapping fix.
8. Hardware claims require observed evidence for the named path.

## Gates for new work

Before adding a transport or backend, record the device lifecycle, report framing, ownership rules, and failure behavior. Before adding a spoof identity, record the exact descriptor, report bytes, and consumer that needs it. Before advertising output, add protocol fixtures and a hardware plan.
