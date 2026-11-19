# Testing the Razer Wolverine V2

For [issue #19][1] and USB device 5426:2601 (1532:0A29 in hexadecimal).

The bundled record comes from Linux's xpad, with the interface-0 endpoints `0x81`/`0x01` taken from a capture. It leaves out these suggested settings, because nothing proves they're needed:

| Left out | Why |
| --- | --- |
| `shareButton` and `paddles` flags | No packet shows where they are, and OJD has no paddle decoder |
| `SetConfiguration1BeforeClaim` | The device reports configuration 1, but nothing shows OJD has to pick it |
| A 200 ms wait after the handshake | No timing evidence |

Not checked: the GIP parser, the Xbox One defaults, the button layout, reconnecting, lights, and rumble.

Checking the file needs no signing. Apple's production USB entitlement doesn't include this ID, so OJD tries IOUSBHost. Use an exact development DEXT only if the ownership report says you need one.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/19

## Check the Bundled Record

From the repository root:

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a29.plist \
  --validate-only
```

Expected:

```text
RECORD_VALIDATION result=valid
```

## Run the Raw USB Probe

1. Quit Steam, games, and controller tools, and plug in with USB.
2. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a29.plist \
     --seconds 45
   ```

3. Check that the controller stays on, `RECORD_HANDSHAKE` succeeds, and `USB_RX` arrives on the captured endpoint.
4. Check the rest position, then press every button, D-pad direction, trigger, stick direction and click, and any extra control.
5. Unplug and plug back in. Do the handshake and one control check again.

If the interface isn't available, keep the road OJD chose and the program that holds it. OJD never detaches the device or falls back to another kind of connection.

## Check Lights and Rumble With an Installed App

Check the light and rumble in an installed app, following [physical output](../physical-output.md) (`ojd` is the [command-line tool](../../../wiki/Command-Line.md)):

```bash
ojd controller list
ojd controller show 1532:0A29
```

Run each step on its own. Write down the player-light result and, where the plan lists them, left, right, and trigger rumble. The plan alone doesn't prove support.

Add the probe output (it holds raw packets, so read it and remove private parts) and the output results to #19, with your macOS version, Mac model, firmware (if you know it), OJD commit, USB road, and the handshake, control, reconnect, light, and motor results.

Endpoint captures, file checks, and plans don't prove support. Write down any missing input, reconnect, light, or output.
