## Why

A ZD O+ Excellence (XInput identity `11C0:5505`) connected by wire on macOS 27.2 enumerates as a Nintendo Switch Pro Controller (`057E:2009`, USB serial `000000000001`) and reports at about 8 ms. On macOS 26.3 the same pad came up in XInput mode at about 1 ms. Its maker has no macOS tool to switch modes. VID `11C0` is Betop/Sanmos.

A community note (Arch Linux gamepad notes) says: "When connected via USB without driver intervention, the microcontroller negotiates a Nintendo Switch HID descriptor before falling back toward generic XInput", and a Linux udev rule `99-zdO-xinput.rules` is used. This is a third-party quote, not checked here.

What the tree shows:

- `057E:2009` is one record bound to `NintendoSwitch1` with no mode match (`Sources/OpenJoystickDriverKit/Resources/Controllers/057e/057e-2009.json:5-14`). Every `057E:2009` pad, genuine or not, gets the Pro Controller driver.
- That protocol sends the USB handshake `80 02`, `80 03`, `80 02`, `80 04` at startup on the `USB` variant for non-Joy-Con layouts (`Sources/OpenJoystickDriverKit/Resources/Protocols/nintendo-switch1.json:57-105`; `Switch1Driver.swift:43` says only a wired Pro Controller takes them).
- `NintendoSwitchInputOnly` declares no startup list in its description head (`nintendo-switch-input-only.json:1-20`, third-party pads such as `0F0D:00C1` and the `33DD` records use it); that no handshake is sent is not verified past line 20.
- No `11C0:5505` record exists; `11C0` has only `11c0-4001.json` (family `SonyDualShock4`, line 10), so an XInput `11C0` pad would need its own record.
- `modeMatch` can select a mode by `link`, `interfaceSignature`, `manufacturer`, `product`, `bcdDevice` and probes, but not by USB serial (`Resources/Schemas/controller.schema.json:132-165`).

Hypothesis, not yet shown: a host handshake (OJD's, or one macOS 27.2 now does) holds the pad in Switch mode, and without one it falls back to `11C0:5505`. The 1 ms versus 8 ms difference could equally be the Switch mode's own report interval. No reporter is available, so the plan does not wait for one: a tester task collects the evidence, and the work that does not need it is planned now.

The G50S in the `unique-virtual-identity` report also shows `057E:2009` with serial `000000000001`. Any match key here must not catch it unless evidence shows that is right.

## What Changes

- A tester task for anyone with an `11C0` ZD pad (below in tasks) records the mode and `bInterval` with OJD stopped and with OJD running, and the `ioreg -l` entry including the USB serial, manufacturer string and `bcdDevice`.
- `ojd diagnose` reports a `057E:2009` controller that reports serial `000000000001`, so a user sees that the pad is a Pro Controller look-alike and why OJD treats it that way.
- Open decision, gated on the tester evidence: (a) bind this pad to a no-handshake path and add an `11c0-5505` record, or (b) document that the pad reports at its own interval in Switch mode. Not implemented until the evidence picks one.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `usb-device-detection`: adds the requirement that `ojd diagnose` reports a `057E:2009` pad with the placeholder serial.

## Impact

- `Sources/OpenJoystickDriverKit/Diagnostics/DiagnosticsService.swift` (`checks`, lines 132-148), `Sources/OpenJoystickDriverCLI/Commands/Diagnose/DiagnoseChecks.swift`, the `Localizable.strings` files for the new message.
- If branch (a) is chosen: `Resources/Controllers/` records (then `./Scripts/ojd catalog regenerate --write` and `./Scripts/ojd driverkit generate`), `Resources/Protocols/`.
- `wiki/Known-Issues.md`, `wiki/Supported-Controllers.md`, `CHANGELOG.md`.
