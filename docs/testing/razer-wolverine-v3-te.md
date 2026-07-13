# Test Razer Wolverine V3 Tournament Edition

This request covers [OpenJoystickDriver issue #14](https://github.com/xsyetopz/OpenJoystickDriver/issues/14) for USB device `5426:2627` (`1532:0A43` in hexadecimal).

The candidate record now selects OJD's wired Xbox One GIP parser instead of `GenericHID`. Its endpoint and mapping details remain unverified. No paid Apple Developer Program account, app signing, application service installation, or DriverKit provisioning is needed for this test.

## Validate the bundled record

From the repository root:

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

Quit Steam, games, and controller utilities. Connect the controller directly by USB, then run:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.json \
  --seconds 30
```

Press and release one control at a time. Confirm that the controller stays powered, `PROFILE_HANDSHAKE` succeeds, `USB_RX` packets arrive, and `EVENT` lines match each control.

If the interface is busy, repeat once with `--detach`, then unplug and reconnect the controller afterward:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.json \
  --seconds 30 --detach
```

Attach the complete output to issue #14 with the macOS version, Mac model, controller firmware if known, exact OJD commit, whether `--detach` was needed, and any missing or incorrect controls. The output can contain raw controller packets; inspect it before publishing.

Passing schema validation alone does not make the record hardware-verified. The record retains `verified: false` until handshake, every input, reconnect, rumble, and lighting behavior claimed by OJD are observed on the device.
