## Context

- The `057E:2009` record has one default mode on `NintendoSwitch1` and no match keys (`057e-2009.json:5-14`).
- `nintendo-switch1.json:57-105` lists four startup output reports (ID 128, bytes `02`, `03`, `02`, `04`) for the `USB` variant. `Switch1Driver.swift:43` documents that only a wired Pro Controller takes them.
- `modeMatch` offers `link`, `interfaceSignature`, `manufacturer`, `product`, `bcdDevice` and probes (`controller.schema.json:132-165`). There is no USB serial key, and the G50S shares serial `000000000001`, so a serial key could not tell the ZD O+ from it anyway.
- `11c0-4001.json` is a `SonyDualShock4` record; it is not a guide for an XInput `11C0` pad. Which family `11C0:5505` needs (probably `XboxXUSB`) is not checked.
- `DiagnosticsService.checks` assembles the `ojd diagnose` checks (`DiagnosticsService.swift:132-148`); the controller list in the snapshot is not read here, so what data the check can reach is unchecked.
- `wiki/Troubleshooting.md:120` says macOS reads some controllers itself in a Switch Pro mode, and `wiki/Known-Issues.md` has no entry for this pad.

## Decisions

### D1: Diagnose First

The ZD O+ cannot be told from a Pro Controller by any key the record format has until the tester supplies `manufacturer`, `product` and `bcdDevice`. The work that needs no evidence is a diagnose check for the placeholder serial, which names the case for users without changing binding.

### D2: Check Does Not Rebind

The check only reports. A serial heuristic as a binding rule is rejected: it would catch the G50S.

## Open

### O1: Branch (a) or (b)

Decided by tester task 1.1. Do not implement either before it.

- (a) OJD's handshake holds the pad in Switch mode. Evidence: with OJD stopped the pad comes up as `11C0:5505` or reports about 1 ms, and with OJD running it shows `057E:2009`. Then: add a second `057E:2009` mode whose `modeMatch` uses the `manufacturer`, `product` or `bcdDevice` the pad reports (only if they differ from a genuine Pro Controller), bound to a no-handshake family (`NintendoSwitchInputOnly` if its description sends none; verify), and add an `11c0-5505` record with the family an XInput pad needs. If the strings do not differ, branch (a) cannot be built without a heuristic and is not built.
- (b) macOS holds it. Evidence: the pad shows `057E:2009` with OJD stopped. Then: the wiki states that in Switch mode the pad reports at its own interval, which OJD cannot change, with the steps a user can take (another USB port or cable, Bluetooth, the pad's own mode switch if it has one; check against the pad's manual).

If the evidence fits neither, leave this open and add a Known Issues entry.
