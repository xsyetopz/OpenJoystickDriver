# Rumble Template Keys

`session.rumble` sits in one mode of a `Controller` record or a `ControllerPatch`. Families that encode rumble from a template take it: `HIDReportLayout`, `HIDDescriptor`, and `VendorPS3ThirdParty`. A `HIDDescriptor` mode takes `Output` or `Feature` only, never `USB`.

| Key | Required | Rule |
| --- | --- | --- |
| `report.kind` | yes | `Output`, `Feature`, or `USB` |
| `report.id` | HID only | 0 to 255; a `USB` report has no `id` |
| `report.length` | yes | HID: 2 to 64 bytes, counting the report ID. `USB`: 1 to 64 |
| `lowFrequency`, `highFrequency`, `leftTrigger`, `rightTrigger` | at least one | `byte`: offset 0 to 63 of the motor intensity |
| motor `encoding` | no | `UInt8` (default), `UInt16BigEndian`, `UInt16LittleEndian`, `SwitchHDRumble` (four bytes) |
| `bytes` | no | Whole report as uppercase hex pairs with single spaces, at most 64. A numbered report starts with its ID. Without it, every byte is 0 except the ID |
| `counter` | no | `byte` 0 to 63 where OJD writes the rolling counter |
| `resendIntervalMilliseconds` | no | 1 to 60000. Resends the last report while a motor runs. Not beside `session.keepAlive` or a family keep-alive |
| `followUp` | no | 1 to 4 whole reports, sent in order after each report that runs a motor, and again on each resend |
| `stop` | no | One whole report, sent in place of the template when every motor is off |

## Byte Rules

- OJD writes the report ID to byte 0 when the ID is not 0, then each motor intensity at its `byte`.
- Motor and counter bytes do not overlap. Each lies after the report ID and inside `report.length`.
- Each `followUp` and `stop` report is exactly `report.length` bytes and starts with the report ID when the ID is not 0.
- Only the main report carries motors and the counter. Follow-up and stop reports go out as written.
- A report with every motor at 0 sends no follow-ups.

## Errors

`ojd record validate` names the key path and the fix. The codes are E5007 messages:

- `session.rumble.followUp`: the list holds fewer than 1 or more than 4 reports.
- `session.rumble.followUp` or `session.rumble.stop`: a report is not the whole report, or lacks the leading report ID.
- `session.rumble.resendIntervalMilliseconds`: the interval is outside 1 to 60000.

Run `ojd explain E5007` for the code.

## Worked Example: DragonRise `0079:0006`

Linux `drivers/hid/hid-dr.c` drives this pad with three 7-byte output reports and report ID 0:

| Report | Bytes |
| --- | --- |
| Motors | `51 00 WEAK 00 STRONG 00 00` |
| Commit, after each motor report | `FA FE 00 00 00 00 00` |
| Stop | `F3 00 00 00 00 00 00` |

The same session in a patch, as JSON for reading (`plutil -convert xml1` writes the property list):

```json
{
  "apiVersion": "openjoystickdriver/v1alpha4",
  "kind": "ControllerPatch",
  "selector": { "vendorID": 121, "productID": 6 },
  "patch": {
    "modes": [{
      "id": "default",
      "session": { "rumble": {
        "report": { "kind": "Output", "id": 0, "length": 7 },
        "bytes": "51 00 00 00 00 00 00",
        "highFrequency": { "byte": 2 },
        "lowFrequency": { "byte": 4 },
        "followUp": ["FA FE 00 00 00 00 00"],
        "stop": "F3 00 00 00 00 00 00"
      } }
    }]
  }
}
```

Pads sold under `0079:0006` differ inside. Set `length` to the output report size the pad's HID descriptor gives. No bundled record declares this template until a motor is felt on hardware.
