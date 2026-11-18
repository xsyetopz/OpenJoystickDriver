# Testing the Razer Wolverine V2

For [issue #19][1] and USB device 5426:2601 (1532:0A29 hexadecimal).

Bundled record: Linux xpad, patched with captured interface-0 endpoints `0x81`/`0x01`. Omitted proposed `shareButton` and `paddles` flags: no packet layout identifies them, and OJD has no paddle decoder.

Also omitted: `SetConfiguration1BeforeClaim` (enumeration reports configuration 1 without showing OJD must select it) and a 200 ms post-handshake delay (no timing evidence). Not verified: GIP parser, Xbox One defaults, input mapping, reconnect, LED, rumble.

Validation needs no signing. The production Apple USB entitlement omits this pair, so the facade tries IOUSBHost; use an exact development DEXT only if ownership evidence requires it.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/19

## Validate the Bundled Record

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

1. Quit Steam, games, and controller tools; connect by USB.
2. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a29.plist \
     --seconds 45
   ```

3. Check the controller stays powered, `RECORD_HANDSHAKE` succeeds, and `USB_RX` arrives on the captured endpoint.
4. Test neutral, press every button, D-pad direction, trigger, stick axis and click, extra control.
5. Reconnect; repeat the handshake and one control check.

Interface unavailable: keep route and registry owner. No detach or cross-transport fallback.

## Check Physical Output With an Installed App

Check LED and rumble in an installed app per [physical output](../physical-output.md) (`ojd` is the [command-line tool](../../../wiki/Command-Line.md)):

```bash
ojd controller list
ojd controller show 1532:0A29
```

Run each step alone. Record the player-indicator result and, where planned, left, right, and trigger rumble. This alone proves no support.

Attach probe output (raw packets; inspect and redact) and output results to #19 with macOS version, Mac model, firmware (if known), OJD commit, USB route, and handshake, control, reconnect, indicator, and actuator results.

Endpoint captures, validation, and plans prove no support. Record missing input, reconnect, indicator, output.
