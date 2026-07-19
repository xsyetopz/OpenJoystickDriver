# #19: Add controller record: Razer Wolverine V2 (1532:0a29)

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/19
- **State:** OPEN
- **Author:** zunium
- **Created:** 2026-07-18T21:00:27Z
- **Updated:** 2026-07-18T22:26:19Z
- **Closed:** —
- **Labels:** enhancement, help wanted

## Report

## Summary

Please add a GIP record for the **Razer Wolverine V2**, USB **`1532:0a29`**. This is a distinct product ID from the already-present `1532-0a43` record. On the current release (0.4.1) the device is detected but falls back to `genericHID` with `mappings=none`, so no input is delivered.

## Device

| Field               | Value                          |
| ------------------- | ------------------------------ |
| Name                | Razer Wolverine V2             |
| Vendor ID           | `0x1532` (5426)                |
| Product ID          | `0x0A29` (2601)                |
| USB product version | `0x0101`                       |
| Class               | `0xFF` (vendor-specific / GIP) |
| Transport           | USB, wired                     |

### USB interface layout (from libusb enumeration)

```
Configuration: 1, 3 interface(s)
  Interface 0 alt=0: class=Vendor sub=0x47
    EP 0x01 OUT Interrupt  maxPkt=64
    EP 0x81 IN  Interrupt  maxPkt=64
  Interface 1 alt=1: class=Vendor sub=0x47
    EP 0x03 OUT Isoch  maxPkt=228
    EP 0x83 IN  Isoch  maxPkt=228
  Interface 2 alt=1: class=Vendor sub=0x47
    EP 0x02 OUT Bulk  maxPkt=64
    EP 0x82 IN  Bulk  maxPkt=64
```

### GIP handshake response

Sending the standard xboxOne GIP startup sequence on interface 0 (`in:0x81`, `out:0x01`) produces a GIP **STATUS/announce** packet, confirming the device speaks GIP:

```
-> 05 20 00 01 00
-> 0A 20 00 03 00 01 14
-> 06 20 00 02 01 00
<- 02 20 XX XX XX XX XX XX XX XX 00 00 32 15 29 0A 01 00 01 00 40 01 02 00 ...   (serial bytes redacted; 32 15 = VID 0x1532, 29 0A = PID 0x0a29)
```

Note: this unit uses endpoints **`in:0x81` / `out:0x01`** (the xbox360-style defaults), not the xboxOne defaults `in:0x82` / `out:0x02`, so the record pins them explicitly.

## Proposed record

Path: `Resources/ControllerOverrides/1532/1532-0a29.json`

```json
{
  "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller-override.schema.json",
  "operation": "add",
  "record": {
    "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller.schema.json",
    "vendor_id": 5426,
    "product_id": 2601,
    "transport": "usb",
    "protocol": {
      "driver": "GIP",
      "variant": "xboxOne",
      "flags": ["shareButton", "paddles"]
    },
    "usb": {
      "endpoints": { "in": 129, "out": 1 },
      "configuration": "set1-before-claim",
      "post_handshake_settle_ms": 200
    },
    "provenance": { "source": "local-hardware", "verified": false }
  }
}
```

## Verification status

- **Confirmed:** with this record present, a source build classifies the device as `parser=GIP protocol=xboxOne endpoints=in:0x81 out:0x1 mappings=shareButton,paddles` (instead of `genericHID`).
- **Not fully confirmed:** end-to-end button/stick decoding, because publishing the virtual device requires the `com.apple.developer.hid.virtual.device` entitlement, which a local dev build cannot obtain. Classification + GIP handshake response are the available evidence. Marked `verified: false` accordingly.

Happy to run any additional capture (`analyze_gamepad.py` diff, raw input dump on a specific endpoint) if useful.

## Comments

### xsyetopz — 2026-07-18T22:04:58Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/19#issuecomment-5013101413)

Latest `0.4.1` does not count right now. It's better to try it on current `0.5.0-alpha.4`, but I'm working on multiple issues on top of existing GH issues.

Patience is key. There is a lot to do! 0.5.0 is to be huge.
