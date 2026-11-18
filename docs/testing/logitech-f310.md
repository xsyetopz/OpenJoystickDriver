# Test Logitech F310 XInput Mapping

[Issue #11][1], device 046d:c21d (1133:49693 decimal).

Linux Xbox 360 packet layout, observed endpoints `0x81`/`0x02`. Check labels in Input Test or with `ojd` ([command-line tool](../../wiki/Command-Line.md)):

```bash
ojd controller watch 046D:C21D
```

Claim support after the reporter confirms the full mapping. Validation needs no signing; raw input needs a development USBDriverKit build with an exact 046D:C21D personality (absent from the production USB entitlement).

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/11

## Validate and Capture

1. Set the F310 switch to X.
2. Quit Steam and other tools.
3. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.plist --validate-only

   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.plist --seconds 45
   ```

4. Press each: A, B, X, Y, LB, RB, Back, Start, Guide, both stick clicks, every D-pad direction, both triggers (rest to fully pressed), both sticks (full range).
5. Check each `USB_RX` packet gives only its `EVENT`.

Interface unavailable: capture `just diagnose-dext`. No detach fallback.

## Verify the App and Consumers

1. In **Controllers**, select the F310, then click **Open Input Test**.
2. Check LB, RB, and each active control match the physical input. No window: use `controller watch`.

Attach to #11: full record-probe output (raw packets; inspect), macOS version, Mac model, OJD commit, switch position, DEXT state, Input Test or CLI results.

Schema validation and fixtures do not replace this.
