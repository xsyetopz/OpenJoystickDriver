# Test a Controller Record

Validates candidate OJD property list records without Apple Developer Program membership. A raw USB probe uses direct IOUSBHost when macOS permits app ownership; a device claimed by the restricted USBDriverKit route also needs the signed application and extension. Supported: raw-USB GIP records, wired or wireless-receiver XUSB records. HID, Bluetooth, other protocols: other tools.

## Prerequisites

1. Install the Xcode command-line tools.
2. Clone OJD:

   ```bash
   xcode-select --install
   git clone https://github.com/xsyetopz/OpenJoystickDriver.git
   cd OpenJoystickDriver
   ```

`--validate-only` needs no paid Apple account, profile, signing, or extension approval. A physical probe through the restricted DEXT route needs:

- Development signing assets: [Signing assets](../development/signing.md)
- Installed, approved `com.openjoystickdriver.XboxUSBDevice` extension signed with the `transport.usb` entitlement
- Host authorized to open its user client

Direct IOUSBHost probes skip the user client. No libusb.

## 1. Save the Candidate Record

Keep the record outside the bundled directory until VID, PID, interface, endpoints, and startup are verified:

```text
/tmp/controller-candidate.plist
```

Use decimal numbers. Review `protocol.initialization` first; the command sends only OJD-modeled startup:

| Record | Startup sent |
| --- | --- |
| GIP | Named initialization actions (driver default when omitted) |
| Xbox 360 wired | Steady Player 1 ring-light packet |
| Xbox 360 wireless receiver | Nothing until a controller connects, then the receiver-wrapped Player 1 packet |
| `XboxGIP/rumble-begin`, `XboxGIP/rumble-end` | Those brief packets, as declared initialization |

`protocol.keepAlive`: optional boolean for GIP records. Default: on. Set false only when device evidence requires it.

## 2. Validate Without Opening Hardware

```bash
just diagnose-record /tmp/controller-candidate.plist --validate-only
```

Expected final line:

```text
RECORD_VALIDATION result=valid
```

Rejected before opening a device: unsupported protocol drivers, HID transports, invalid endpoint directions and variants, unknown startup packet names.

## 3. Probe the Physical Controller

1. Quit games, Steam, and other controller tools.
2. Install and approve a signed development build.
3. Connect the controller by USB.
4. Run:

   ```bash
   just diagnose-record /tmp/controller-candidate.plist --seconds 30
   ```

5. During the capture, press one control at a time, returning to neutral.

| Output line | Meaning |
| --- | --- |
| RECORD | Identity, endpoints, configuration resolved for the matched device, startup names. With --validate-only, the record's own values |
| USB_DEVICE, USB_CLAIM | Matched physical USB path |
| RECORD_BINDING result=refused | Interface violates the record's contract, or the configuration descriptor was unreadable. Exit code 4, before the probe opens or writes to the device |
| RECORD_HANDSHAKE | Whether protocol startup completed |
| USB_TX | Additional Xbox 360 startup output |
| USB_RX | Every received input packet |
| EVENT | Parser output for changed controls |
| RECORD_SUMMARY | Packet, parsed-event, parse-error counts |

| Refusal `reason` | Meaning and action |
| --- | --- |
| device-in-use | Host refused the read and names the program holding the device; close it |
| configuration-unreadable | Another read failure; reconnect and retry |
| configuration-unobserved | Facts read belong to another service; retry |

Interface unavailable: keep the route and live registry owner. Model requires the restricted extension: `just diagnose-dext`. No detach or cross-transport fallback.

## 4. Report Results

Say which subject produced the behavior:

| Subject | Report |
| --- | --- |
| Installed app / shared DMG | DMG filename; attach `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG; for an installed copy also run `ojd diagnose --output support-report.json` |
| Source-built record probe | Checkout commit and working-tree state, record path, full `just diagnose-record ...` command and output. Says nothing about the installed app or a shared DMG |

The diagnose run exercises the packaged Developer ID-signed app and its embedded DEXT, not a checkout. The notarized, stapled tester package can replace the DriverKit extension with SIP enabled. `controllers[].binding` and `unboundDevices[]` show how OJD classified each connection: outcome, reason, rule, matched predicates, catalog record ID, access backend, interface summaries, rejected candidates. Only whether a serial number exists is recorded, never its value; no packet payloads.

Do not mix them: a source probe can validate a record while an older installed app or DEXT still produces the behavior.

Attach the full command, output, and these to the controller's GitHub issue:

| Item |
| --- |
| macOS version and Mac model |
| Controller name and connection mode |
| OJD commit |
| Installed artifact: tester DMG filename; `version` (SemVer with `+build.<number>.sha.<commit>` metadata) and `bundle_version` from the build-info file |
| Record property list |
| USB route, with DriverKit extension version and activation state when applicable |
| Whether the controller stayed powered on |
| Neutral plus one press/release for every control |
| Missing, duplicated, delayed, or wrong EVENT lines |
| Any PARSE_ERROR or zero-packet summary |

Schema validation proves only that the record is well formed. Record input, reconnect, rumble, and LED observations in the matching testing document and issue; add no verification metadata to the runtime record.
