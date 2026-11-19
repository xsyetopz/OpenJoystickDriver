# Test Razer Wolverine V3 Tournament Edition

For [issue #14][1] and USB device 5426:2627 (1532:0A43 in hexadecimal).

The draft record uses the wired Xbox One GIP parser, not `HIDDescriptor`, and sets endpoints IN `0x81` and OUT `0x01`. Pull request #39 reported that the startup handshake worked, the light came on, and buttons, sticks, triggers, and D-pad worked, but attached no capture. The record has no `shareButton` or `paddles` flag, because no packet shows them and OJD has no paddle decoder.

There's no capture of input or output yet. Checking the file needs no signing. Apple's production USB entitlement doesn't include this ID, so OJD tries IOUSBHost. Use an exact development DEXT only if the ownership report says you need one.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/14

## Check the Bundled Record

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

1. Quit Steam, games, and controller tools, and plug in with USB.
2. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.plist \
     --seconds 30
   ```

3. Press and let go of each control. Check that the controller stays on, `RECORD_HANDSHAKE` succeeds, `USB_RX` lines arrive, and the `EVENT` lines match.

If the interface isn't available, keep the road OJD chose and the program that holds it. OJD never detaches the device or falls back to another kind of connection.

Add the full output (it holds raw packets, so read it first) to #14 with your macOS version, Mac model, firmware (if you know it), OJD commit, USB road, and any missing or wrong controls.

Passing the schema check doesn't mean it's supported. Write down whether the handshake, input, reconnecting, rumble, and lights worked.
