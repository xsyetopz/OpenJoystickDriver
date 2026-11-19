# Test the Nacon Revolution X Pro

USB device 12933:1588 (3285:0634 in hexadecimal), for [issue #21](https://github.com/xsyetopz/OpenJoystickDriver/issues/21).

The record isn't confirmed on hardware yet. It picks `XboxGIP` on interface 0, with interrupt IN `0x87` and OUT `0x07`. It turns off the `0x03` "are you there?" packet the Mac normally sends now and then, because a report said it made the controller drop out. The WebUSB result in the issue came from a browser, not from OJD's USBDriverKit road.

## Check the Bundled Record

From the repository root:

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/3285/3285-0634.plist \
  --validate-only
```

Expected:

```text
RECORD_VALIDATION result=valid
```

## Run the Raw USB Probe

Apple's production USB entitlement doesn't include this VID/PID, so OJD tries IOUSBHost.

1. Quit games, Steam, and controller tools. Plug in with USB.
2. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/3285/3285-0634.plist \
     --seconds 45
   ```

3. Check that `RECORD_HANDSHAKE` succeeds, `USB_RX` keeps arriving, and no `USB_KEEPALIVE` line prints.
4. Press every button, D-pad direction, trigger, stick direction and click, and Guide.
5. Leave it alone for longer than four seconds, the usual "are you there?" gap. It must stay connected without a `0x03` from the Mac.
6. Unplug and plug back in. Do the handshake and one control check again.

If the interface isn't available, write down the road OJD chose and the program that holds it. Don't add a detach fallback or widen the production DEXT. Use a development DEXT only if the ownership report says you need one.

Parser test files cover packets that are split, stacked, extra-long, or asking for an ACK. Real runs must show a steady USB connection and controls reaching the virtual gamepad.

## Check Lights and Rumble With an Installed App

Check the light and rumble in an installed app, following [physical output](physical-output.md) (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

```bash
ojd controller list
ojd controller show 3285:0634
```

Add the results to #21 with your macOS version, Mac model, firmware (if you know it), OJD commit, USB road, ownership results, and any transfer error.

Call it supported only after input, reconnecting, and output pass on hardware.
