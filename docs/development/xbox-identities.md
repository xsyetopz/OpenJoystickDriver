# Xbox Fallback Identities

A safe published virtual profile needs more than a product name:

1. an exact virtual VID/PID;
1. the matching descriptor and report bytes;
1. a live `GCController.supportsHIDDevice` result where GameController.framework matters;
1. hardware evidence for GameController.framework claims.

OJD publishes exactly two virtual HID profiles, `hid-xbox-one-s-bt` and `hid-generic`; `VirtualHIDProfileSelector` picks `hid-xbox-one-s-bt` when a controller's declared controls fit it, otherwise `hid-generic`. See [CLI and Application Runtime](cli-and-runtime.md) for the selection and override contract.

Linux `xpad.c` identifies physical devices for Linux. It does not prove that a macOS virtual HID device can impersonate them.

## Evidence: hid-xbox-one-s-bt

No published profile is an Xbox One Bluetooth-shaped spoof beyond the current one. Earlier `045e:02fd` / BT1/BT2 experiments produced no usable SDL HIDAPI input and were retired; `hid-xbox-one-s-bt` now publishes `045e:02fd` with an approximated descriptor pending a genuine capture. GameSir G7 SE USB GIP is hardware-verified for GameController.framework. Physical GIP sends Hello plus one rest `0x20`, then change-only input; a status-only packet log after that is not a failed init. A custom SDL 3.4.16 HIDAPI xboxone build bound the Bluetooth `045e:0b13` identity and used the 17-byte BLE path; a 12s interrupt watch stayed idle (no physical button). Steam `hid_init` still hangs. Explicit picker DualShock 4 / DualSense from that GIP pad returned `GCController.supportsHIDDevice` and custom HIDAPI `SDL_OpenGamepad`, from a period when OJD offered a per-family picker; the current profile set has no DualShock 4 or DualSense equivalent.

OJD has several physical records and parsers for other Xbox controller families but no distinct virtual profile beyond `hid-xbox-one-s-bt` and `hid-generic`.

## Apple Audit

The GameController MobileAsset version `10.5.2` downloaded on 2026-07-12 had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. This applies only to that system and asset version. Check again after macOS or MobileAsset updates:

```bash
ojd diagnose --bundle /tmp/ojd-support.json
jq .appleGameControllerAudit /tmp/ojd-support.json
```

The support report from the app uses the same audit.

## Selection and Overrides

`VirtualHIDProfileSelector` does not persist its own choice; it runs automatically unless the controller's model (vendor/product) has a stored override. Automatic selection carries no regard for protocol family or foreground consumer; today both profiles carry every primary control, so automatic selection always picks `hid-xbox-one-s-bt` when it fits, else `hid-generic`.

## Promotion Checks

Promoting `hid-xbox-one-s-bt`'s approximated `045e:02fd` descriptor to a genuine capture needs a verified consumer result from SDL and GameController probes covering input, reconnect, rumble, and lights before the descriptor changes.
