# Test Razer Wolverine V3 Tournament Edition

For [issue #14][1] and USB device 5426:2627 (1532:0A43 hexadecimal).

The candidate record selects the wired Xbox One GIP parser, not `HIDDescriptor`, with patch endpoints IN `0x81`, OUT `0x01`. Pull request #39 reported a handshake, LED on, and working buttons, sticks, triggers, D-pad; no capture is attached. No `shareButton` or `paddles` flags: no packet evidence, and OJD has no paddle decoder.

Input and output: no capture. Validation needs no signing. The production Apple USB entitlement omits this pair, so the facade tries IOUSBHost; use an exact development DEXT only if ownership evidence requires it.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/14

## Validate the Bundled Record

From the repository root:

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.plist \
  --validate-only
```

Expected:

```text
RECORD_VALIDATION result=valid
```

## Run the USB Probe

1. Quit Steam, games, and controller tools; connect by USB.
2. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.plist \
     --seconds 30
   ```

3. Press and release each control. Check the controller stays powered, `RECORD_HANDSHAKE` succeeds, `USB_RX` arrives, and `EVENT` lines match.

Interface unavailable: keep route and registry owner; no detach or cross-transport fallback.

Attach full output (raw packets; inspect first) to #14 with macOS version, Mac model, firmware (if known), OJD commit, USB route, missing or wrong controls.

Schema validation proves no support. Record missing handshake, input, reconnect, rumble, lighting.
