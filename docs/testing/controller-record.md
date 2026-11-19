# Test a Controller Record

A controller record is a recipe file that tells OJD how one controller talks. This page shows how to test a new record before it ships. You don't need a paid Apple developer account.

Which tool fits:

| Record | Tool |
| --- | --- |
| Raw-USB GIP | This page |
| Wired XUSB, or XUSB through a wireless receiver | This page |
| HID, Bluetooth, other protocols | Other tools |

A raw USB probe talks to the controller through IOUSBHost directly when macOS lets the app take it. A controller that only the restricted USBDriverKit road can claim also needs the signed app and its extension.

## Before You Start

1. Install the Xcode command-line tools.
2. Download OJD:

   ```bash
   xcode-select --install
   git clone https://github.com/xsyetopz/OpenJoystickDriver.git
   cd OpenJoystickDriver
   ```

`--validate-only` needs no paid Apple account, profile, signing, or extension approval. A probe of a real controller through the restricted DEXT road needs:

- development signing files: [Signing assets](../development/signing.md)
- the `com.openjoystickdriver.XboxUSBDevice` extension, installed, approved, and signed with the `transport.usb` entitlement
- permission for the app to open the extension's user client

Direct IOUSBHost probes skip the user client. OJD doesn't use libusb.

## 1. Save the Record Somewhere Safe

Keep the record outside the bundled folder until you've checked the VID, PID, interface, endpoints, and startup:

```text
/tmp/controller-candidate.plist
```

Write numbers in decimal. Read `protocol.initialization` first. The command sends only the startup packets OJD knows:

| Record | Startup packets sent |
| --- | --- |
| GIP | The named startup actions (the driver's default when you leave them out) |
| Xbox 360 wired | A steady Player 1 ring-light packet |
| Xbox 360 wireless receiver | Nothing until a controller connects, then the Player 1 packet wrapped for the receiver |
| `XboxGIP/rumble-begin`, `XboxGIP/rumble-end` | Those short packets, when listed in the startup |

`protocol.keepAlive` is an optional true or false for GIP records, and it's on by default. Turn it off only when the device clearly needs that.

## 2. Check the File Without Touching Hardware

```bash
just diagnose-record /tmp/controller-candidate.plist --validate-only
```

The last line should be:

```text
RECORD_VALIDATION result=valid
```

OJD refuses these before it opens any device: protocol drivers it doesn't have, HID connections, endpoints that point the wrong way or use the wrong variant, and startup packet names it doesn't know.

## 3. Test the Real Controller

1. Quit games, Steam, and other controller tools.
2. Install and approve a signed development build.
3. Plug the controller in with USB.
4. Run:

   ```bash
   just diagnose-record /tmp/controller-candidate.plist --seconds 30
   ```

5. While it records, press one control at a time and let it go back to rest.

What each output line means:

| Line | Meaning |
| --- | --- |
| RECORD | The identity, endpoints, setup, and startup names OJD worked out for the matched device. With --validate-only, the record's own values |
| USB_DEVICE, USB_CLAIM | Which physical USB device matched |
| RECORD_BINDING result=refused | The interface breaks the record's rules, or OJD couldn't read the configuration descriptor. Exit code 4, before the probe opens or writes to the device |
| RECORD_HANDSHAKE | Whether the startup finished |
| USB_TX | Extra Xbox 360 startup packets OJD sent |
| USB_RX | Every input packet received |
| EVENT | What the parser read, for each control that changed |
| RECORD_SUMMARY | How many packets, events, and parse errors |

If OJD refuses, the `reason` says why:

| `reason` | Meaning and what to do |
| --- | --- |
| device-in-use | macOS refused the read and names the program holding the device. Close that program |
| configuration-unreadable | Some other read failure. Unplug, plug back in, and try again |
| configuration-unobserved | What OJD read belongs to another service. Try again |

If the interface isn't available, keep the road OJD chose and the program that holds it in the live registry. When the model needs the restricted extension, run `just diagnose-dext`. OJD never detaches the device or falls back to another kind of connection.

## 4. Report What You Found

Say which build made the behavior you saw:

| Build | What to send |
| --- | --- |
| Installed app or shared DMG | The DMG filename and `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG. For an installed copy, also run `ojd diagnose --output support-report.json` |
| Record probe built from source | The checkout commit and whether it had local changes, the record path, and the full `just diagnose-record ...` command and output. This says nothing about the installed app or a shared DMG |

`ojd diagnose` tests the packaged app signed with Developer ID and the DEXT inside it, not a source checkout. The notarized, stapled tester package can replace the DriverKit extension while SIP stays on. `controllers[].binding` and `unboundDevices[]` show how OJD sorted each connection: outcome, reason, rule, which tests matched, catalog record ID, access backend, interface summaries, and candidates it turned down. The report notes only whether a serial number exists, never the number itself, and holds no packet contents.

Keep the two apart. A source probe can pass a record while an older installed app or DEXT is still the thing you're watching.

Add the full command, the output, and these to the controller's GitHub issue:

| Item |
| --- |
| macOS version and Mac model |
| Controller name and how it's connected |
| OJD commit |
| Installed build: tester DMG filename; `version` (SemVer with `+build.<number>.sha.<commit>` metadata) and `bundle_version` from the build-info file |
| Record property list |
| USB road, plus the DriverKit extension version and whether it's active, when that applies |
| Whether the controller stayed on |
| The resting state, plus one press and release of every control |
| Missing, doubled, late, or wrong EVENT lines |
| Any PARSE_ERROR, or a summary with zero packets |

Schema validation only proves the file is shaped right. Write input, reconnect, rumble, and light results in the matching testing document and issue, and never add test results to the record itself.
