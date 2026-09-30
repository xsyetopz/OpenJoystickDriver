# Probes

## Contents

- [Choose the probe](#choose-the-probe)
- [Record-probe markers](#record-probe-markers)
- [Failure meanings](#failure-meanings)

## Choose the probe

**Definition.** Each `./Scripts/ojd diagnose` command answers one question. Run `./Scripts/ojd --help` to see the current list.

| Question | Command |
| --- | --- |
| Does a candidate record satisfy the record contract? | `./Scripts/ojd diagnose record <json> --validate-only` |
| Does the record open, handshake, and decode on this device? | `./Scripts/ojd diagnose record <json> --seconds N` |
| Is the DEXT activated, signed, in IORegistry, and connected to the app service? | `./Scripts/ojd diagnose dext` |
| Does SDL3 see the virtual device? | `./Scripts/ojd diagnose sdl3 [--seconds N]` |
| Does SDL3 through GameController/MFI see it, and does rumble reach it? | `./Scripts/ojd diagnose sdl3-gamecontroller [--seconds N]` |
| Does SDL3's Xbox 360 HIDAPI path see it, and does rumble reach it? | `./Scripts/ojd diagnose sdl3-hidapi-x360 [--seconds N]` |
| Does GameController.framework list it? | `./Scripts/ojd diagnose gamecontroller` |
| Which physical motor is which? | `./Scripts/ojd diagnose rumble-motors <vid> <pid> [intensity] [duration-ms]` (interactive, drives motors) |
| Does a macOS 10.15 test bundle run? | `./Scripts/ojd diagnose catalina [app]` |

**Use when.** Pick the one probe whose answer decides the question.

**Do not use when.** The candidate record has not passed `--validate-only`. A live probe of an invalid record fails on the record, not on the device.

**Verify.** Each command exits 0 and prints its result lines. A non-zero exit leaves the claim unproven.

## Record-probe markers

**Definition.** `diagnose record` (implemented in `Sources/OpenJoystickDriverHIDTool/ControllerRecordProbeRunner.swift`) prints one line per event to stdout, in this order. Errors go to stderr as `ERROR: ...`.

| Marker | Meaning |
| --- | --- |
| `RECORD identity=... vid=... pid=... driver=...` | The plan being probed, with its startup bytes |
| `RECORD_VALIDATION result=valid` | The candidate passed the record contract (`--validate-only` stops here) |
| `USB_MATCHES count=N` | Raw USB devices matching the VID/PID |
| `USB_DEVICE`, `USB_STRING` | The device chosen, and its product string |
| `RECORD_BINDING result=refused reason=...` | The device violates the record's interface contract; nothing was written |
| `USB_CONFIGURATION`, `USB_ALTERNATE_SETTING`, `USB_OPEN` | The interface was configured and opened |
| `USB_TX` | A startup, lifecycle, or driver write (`result=ignored` for a tolerated failure) |
| `RECORD_HANDSHAKE driver=... result=complete` | Every startup write succeeded. Printed only on success |
| `USB_RX` | An input transfer |
| `USB_KEEPALIVE result=sent` or `result=error` | A keep-alive write |
| `EVENT` | A parser event decoded from input |
| `CONTROLLER_CONNECTION state=...` | Connection-state transition |
| `PARSE_ERROR` | The parser rejected a report |
| `RECORD_SUMMARY packets=N events=N parse_errors=N` | Final counts for the run |

Exit statuses: `0` at least one packet arrived (even with parse errors), `1` an error was thrown (including a failed startup write), `2` no matching raw USB device, `3` zero packets, `4` binding refused.

**Use when.** Reading any live record-probe output.

**Example.** A healthy run shows `USB_DEVICE`, `USB_OPEN`, the startup `USB_TX` lines, `RECORD_HANDSHAKE ... result=complete`, then repeated `USB_RX` followed by `EVENT` lines that change when a control is pressed, and finally a `RECORD_SUMMARY` with non-zero packets and `parse_errors=0`.

**Verify.** The report quotes, redacted:

1. The `RECORD_VALIDATION` line from the `--validate-only` run.
1. The `RECORD_HANDSHAKE` line, or states that it is absent and quotes the `ERROR:` line and exit status instead. An absent handshake line means the startup failed; it is not a formatting gap.
1. The `RECORD_BINDING` line, when present.
1. One `USB_RX`/`EVENT` pair for each control claimed.
1. The `RECORD_SUMMARY` line and the exit status. Exit `0` alone does not show that decoding worked; read `parse_errors` and the `EVENT` lines.

## Failure meanings

| Observation | The only safe conclusion |
| --- | --- |
| No native or OJD listing | No discovery evidence in this session |
| Listed but busy | Another owner may hold the interface |
| `RECORD_VALIDATION` not valid | The candidate violates the record contract |
| `RECORD_BINDING result=refused` | The device's interface does not match the record; the device was not written to |
| No `RECORD_HANDSHAKE` line, exit `1`, or power loss | The declared startup is not accepted |
| Zero `USB_RX` | No input evidence |
| Packets plus `PARSE_ERROR` | Parser and observed framing disagree |
| Missing or wrong `EVENT` lines | The input claim is not proven |
| Reconnect loses lifecycle | The reconnect claim is not proven |
| Output plan absent or a step fails | That output capability is unverified |

**Use when.** Before writing any conclusion from a failed or partial run.

**Do not use when.** Never widen a row. "Zero `USB_RX`" does not mean that the controller is unsupported. It means only that this run captured no input.

**Verify.** Every conclusion in the report maps to one row of this table.
