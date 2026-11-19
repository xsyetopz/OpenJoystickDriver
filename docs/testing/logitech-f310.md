# Test Logitech F310 XInput Mapping

[Issue #11][1], device 046d:c21d (1133:49693 in decimal).

With its switch on X, the F310 speaks the same USB language as a wired Xbox 360 controller, the one Linux uses. Its endpoints were seen as `0x81` and `0x02`. Check the labels in Input Test, or with `ojd` ([command-line tool](../../wiki/Command-Line.md)):

```bash
ojd controller watch 046D:C21D
```

Call it supported only after the person who reported it confirms every control. Checking the file needs no signing. Reading raw input needs a development USBDriverKit build with an exact 046D:C21D personality, because Apple's production USB entitlement doesn't include this ID.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/11

## Check and Capture

1. Set the F310's switch to X.
2. Quit Steam and other controller tools.
3. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.plist --validate-only

   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-c21d.plist --seconds 45
   ```

4. Press each of these: A, B, X, Y, LB, RB, Back, Start, Guide, both stick clicks, every D-pad direction, both triggers (from rest to all the way down), and both sticks (all the way around).
5. Check that each `USB_RX` packet gives only the `EVENT` for the control you pressed.

If the interface isn't available, capture `just diagnose-dext`. OJD never detaches the device as a fallback.

## Check the App and Games

1. In **Controllers**, select the F310 and click **Open Input Test**.
2. Check that LB, RB, and every other control match what you press. If the window won't open, use `controller watch`.

Add to #11: the full record-probe output (it holds raw packets, so read it first), macOS version, Mac model, OJD commit, switch position, extension state, and the Input Test or CLI results.

Schema checks and test files don't replace this.
