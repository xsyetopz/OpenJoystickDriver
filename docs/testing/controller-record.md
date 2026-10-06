# Test a Controller Record

Validate candidate OJD JSON records without Apple Developer Program membership. A raw USB probe uses direct IOUSBHost when macOS permits app ownership. A device claimed by OJD's restricted USBDriverKit route also requires the signed application and extension.

The probe supports raw-USB `GIP` records and wired or wireless-receiver `XUSB` records. HID, Bluetooth, and unknown protocols need their own tools.

## Prerequisites

Install the Xcode command-line tools, then clone OJD:

```bash
xcode-select --install
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
```

`--validate-only` needs no paid Apple account, provisioning profile, application signing, or system-extension approval. A physical probe through the restricted DEXT route requires the development signing assets described in [Signing assets](../development/signing.md), an installed and approved `com.openjoystickdriver.XboxUSBDevice` extension signed with the `transport.usb` entitlement, and a host authorized to open its user client. Direct IOUSBHost probes do not use that user client. OJD does not use libusb.

## 1. Save the Candidate Record

Save the proposed controller JSON outside the bundled record directory until you verify its VID, PID, interface, endpoints, and startup behavior. For example:

```text
/tmp/controller-candidate.json
```

Use decimal numbers in the JSON. Before probing, review `protocol.initialization`. The command sends only OJD-modeled startup behavior:

- GIP: the named initialization actions (the driver default when omitted); profiles may disable the default keep-alive when hardware evidence requires it.
- Xbox 360 wired: the steady Player 1 ring-light packet.
- Xbox 360 wireless receiver: no output until a logical controller connects, then the receiver-wrapped steady Player 1 packet.
- A record containing `xbox.gip/rumble-begin` and `xbox.gip/rumble-end` sends those brief initialization packets because they are part of that record's declared initialization.

`protocol.keepAlive` is an optional boolean for GIP records. Omit it to keep the default-enabled behavior. Set it to `false` only when device evidence requires periodic host output to be disabled.

## 2. Validate Without Opening Hardware

```bash
./Scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
```

Expected output ends with:

```text
RECORD_VALIDATION result=valid
```

Validation rejects unsupported protocol drivers, HID transports, invalid endpoint directions, invalid variants, and unknown startup packet names before opening a device.

## 3. Probe the Physical Controller

Quit games, Steam, and other controller tools first. Install and approve a signed development build, connect the controller directly by USB, then run:

```bash
./Scripts/ojd diagnose record /tmp/controller-candidate.json --seconds 30
```

During the capture, press one control at a time and return it to neutral. The probe prints:

- `RECORD`: the exact identity, the endpoints and configuration resolved for the matched device, and startup names. With `--validate-only` it shows the record's own values.
- `USB_DEVICE` and `USB_CLAIM`: the matched physical USB path.
- `RECORD_BINDING result=refused`: the observed interface violates the record's interface contract, or (`reason=configuration-unobserved`) the device's configuration descriptor could not be read; retry that case. The probe exits with code 4 before it opens or writes to the device.
- `RECORD_HANDSHAKE`: whether the protocol startup completed.
- `USB_TX`: additional Xbox 360 startup output.
- `USB_RX`: every received input packet.
- `EVENT`: OJD parser output for changed controls.
- `RECORD_SUMMARY`: packet, parsed-event, and parse-error counts.

If the interface is unavailable, preserve the selected route and live registry owner. Use `./Scripts/ojd diagnose dext` when the selected model requires the restricted extension. There is no detach or cross-transport fallback.

## 4. Report Results

Identify the distribution path that produced the behavior. An installed app and a source-built record probe are different test subjects:

- **Installed app / shared DMG:** report the exact DMG filename and attach `OpenJoystickDriver-TESTER-BUILD.txt` from the DMG. For an installed copy, also run:

  ```bash
  ojd diagnose --bundle support-report.json
  ```

  This exercises the packaged Developer ID-signed app and its embedded DEXT; it does not use the Swift sources in a checkout. The notarized, stapled community tester package can replace the DriverKit extension with SIP enabled. The report's `controllers[].binding` and `unboundDevices[]` show how each connection was classified: outcome, reason, rule, matched predicates, catalog record ID, access backend, interface summaries, and rejected candidates. It records only whether a serial number is present, never its value, and no packet payloads.
- **Source-built record probe:** report the checkout commit and working-tree state, the record path, and the complete `./Scripts/ojd diagnose record ...` command and output. This route builds/runs the probe from the current source checkout and is not evidence about the installed app or a shared DMG.

Do not mix these reports: a source probe can validate a record while an older installed app or DEXT is still the behavior being observed, and an installed DMG cannot prove that an uncommitted source change was included.

Attach the complete command, output, and these details to the controller's GitHub issue:

- macOS version and Mac model
- controller name and connection mode
- exact OJD commit
- shared tester DMG filename and build-info file when testing an installed artifact
- tester `version` (SemVer with `+build.<number>.sha.<commit>` metadata) and `bundle_version` from the build-info file when testing an installed artifact
- exact record JSON
- selected USB route; include DriverKit extension version and activation state when applicable
- whether the controller stayed powered on
- neutral plus one press/release for every control
- any missing, duplicated, delayed, or incorrect `EVENT` lines
- any `PARSE_ERROR` or zero-packet summary

Schema validation proves only that the operational record is well formed. Record correct input, stable reconnect, and any claimed rumble or LED observations in the matching testing document and issue; do not add verification metadata to the runtime record.
