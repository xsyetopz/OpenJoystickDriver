# Test a controller record

You can validate a candidate OJD JSON record without an Apple Developer Program membership. A raw
USB probe uses direct IOUSBHost when macOS permits app ownership. A device claimed by OJD's
restricted USBDriverKit route also requires the signed application and extension.

The probe supports raw-USB `GIP` records and wired or wireless-receiver `Xbox360` records. HID, Bluetooth, and unknown protocols need their own tools.

## Prerequisites

Install the Xcode command-line tools, then clone OJD:

```bash
xcode-select --install
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
```

`--validate-only` needs no paid Apple account, provisioning profile, application
signing, or system-extension approval. A physical probe through the restricted
DEXT route requires the development signing assets described in
[Signing assets](../development/signing.md), an installed and approved
`com.openjoystickdriver.XboxUSBDevice` extension, and a host authorized to open
its user client. Direct IOUSBHost probes do not use that user client. OJD does
not use libusb.

## 1. Save the candidate record

Save the proposed controller JSON outside the bundled record directory until you verify its VID, PID, interface, endpoints, and startup behavior. For example:

```text
/tmp/controller-candidate.json
```

Use decimal numbers in the JSON. Before probing, review `protocol.startup_packets`. The command sends only the startup behavior already modeled by OJD:

- GIP: the named startup sequence; profiles may disable the default keep-alive
  when hardware evidence requires it.
- Xbox 360 wired: the steady Player 1 ring-light packet.
- Xbox 360 wireless receiver: no output until a logical controller connects, then the receiver-wrapped steady Player 1 packet.
- A record containing `rumbleBegin` and `rumbleEnd` sends those brief initialization packets because they are part of that record's declared startup sequence.

`protocol.keep_alive` is an optional boolean for GIP records. Omit it to keep
the default-enabled behavior. Set it to `false` only when device evidence
requires periodic host output to be disabled.

## 2. Validate without opening hardware

```bash
./scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
```

Expected output ends with:

```text
RECORD_VALIDATION result=valid
```

Validation rejects unsupported protocol drivers, HID transports, invalid endpoint directions, invalid variants, and unknown startup packet names before opening a device.

## 3. Probe the physical controller

Quit games, Steam, and other controller tools first. Install and approve a signed
development build, connect the controller directly by USB, then run:

```bash
./scripts/ojd diagnose record /tmp/controller-candidate.json --seconds 30
```

During the capture, press one control at a time and return it to neutral. The probe prints:

- `RECORD`: the exact identity, endpoints, configuration behavior, and startup names.
- `USB_DEVICE` and `USB_CLAIM`: the matched physical USB path.
- `RECORD_HANDSHAKE`: whether the protocol startup completed.
- `USB_TX`: additional Xbox 360 startup output.
- `USB_RX`: every received input packet.
- `EVENT`: OJD parser output for changed controls.
- `RECORD_SUMMARY`: packet, parsed-event, and parse-error counts.

If the interface is unavailable, preserve the selected route and live registry
owner. Use `./scripts/ojd diagnose dext` when the selected model requires the
restricted extension. There is no detach or cross-transport fallback.

## 4. Report results

Attach the complete command and output to the controller's GitHub issue. Include:

- macOS version and Mac model
- controller name and connection mode
- exact OJD commit
- exact record JSON
- selected USB route; include DriverKit extension version and activation state when applicable
- whether the controller stayed powered on
- neutral plus one press/release for every control
- any missing, duplicated, delayed, or incorrect `EVENT` lines
- any `PARSE_ERROR` or zero-packet summary

Do not mark the record hardware-verified merely because validation passes. A hardware-verified record needs correct input for every control, stable reconnect, and any claimed rumble or LED behavior checked on the physical controller.
