# Test Razer Wolverine V3 Tournament Edition

This test covers [OpenJoystickDriver issue #14](https://github.com/xsyetopz/OpenJoystickDriver/issues/14) for USB device `5426:2627` (`1532:0A43` in hexadecimal).

The candidate record selects OJD's wired Xbox One GIP parser instead of `GenericHID` and uses the parser defaults. It declares no `shareButton` or `paddles` flags. The request proposed those flags without packet evidence, and OJD has no paddle packet decoder.

The endpoint, input mapping, and output details remain unverified. Validation is
signing-free. This pair is not in the current production Apple USB entitlement,
so the USB facade tries direct IOUSBHost. Use an exact development DEXT experiment
only if live ownership evidence requires it.

## Validate the bundled record

Run this command from the repository root:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.json \
  --validate-only
```

Expected result:

```text
PROFILE_VALIDATION result=valid
```

## Run the USB probe

Quit Steam, games, and controller utilities. Connect the controller directly by USB. Then run:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.json \
  --seconds 30
```

Press and release one control at a time. Confirm that the controller stays powered, `PROFILE_HANDSHAKE` succeeds, `USB_RX` packets arrive, and `EVENT` lines match each control.

If the interface is unavailable, preserve the selected route and registry owner;
there is no detach or cross-transport fallback.

Attach the complete output to issue #14 with the macOS version, Mac model,
controller firmware if known, exact OJD commit, selected USB route, and any missing or
incorrect controls. The output can contain raw controller packets; inspect it
before publishing.

Passing schema validation alone does not prove complete support. Keep the testing document explicit
about missing handshake, input, reconnect, rumble, and lighting observations until they are observed
on the device.
