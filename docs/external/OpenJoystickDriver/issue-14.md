# #14: Device support request: Razer Wolverine V3 Tournament Edition (1532:0A43)

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/14
- **State:** OPEN
- **Author:** cbandras
- **Created:** 2026-07-06T23:14:27Z
- **Updated:** 2026-07-12T05:51:13Z
- **Closed:** —
- **Labels:** enhancement, help wanted

## Report

## Device support request: Razer Wolverine V3 Tournament Edition (RZ06-0521)

**Summary**
Requesting a device profile for the Razer Wolverine V3 Tournament Edition, an Xbox-licensed wired GIP controller. It currently falls back to GenericHID since it's not in the catalog, and the controller's firmware never completes its handshake in that mode (it blinks, then powers off after a timeout). 

**Device details**
- Product: Razer Wolverine V3 Tournament Edition for Xbox
- Model No: RZ06-0521
- VID:PID: 1532:0A43
- Connection: USB-C wired only (no Bluetooth/wireless)
- Confirmed working on Windows/Xbox via standard GIP

**What I've verified so far**
- Controller enumerates correctly on macOS (Tahoe) and is recognized by name and VID:PID in OJD's Input Test window
- Currently tagged "GenericHID" with no live stick/button input registering
- Physical light blinks continuously after the macOS "Allow accessory" prompt, then the controller powers off after a timeout, consistent with a firmware waiting for a GIP handshake it never receives

**Draft profile**
Based on the existing GameSir G7 SE profile (same category: third-party wired Xbox-licensed GIP controller with paddles), attached below. I haven't been able to test this myself since building from source requires DriverKit provisioning profiles I don't have (no Apple Developer Program account), so I'm not able to confirm whether the endpoint numbers or startup packet sequence need adjustment. 

```json
{
  "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller-profile.schema.json",
  "profile_version": "1.0.0",
  "identity": {
    "vendor_id": 5426,
    "product_id": 2627,
    "name": "Razer Wolverine V3 Tournament Edition",
    "short_name": "WolverineV3TE"
  },
  "input": {
    "transport": "usb",
    "usb": {
      "class": 255,
      "interface": 0,
      "endpoints": {
        "in": 130,
        "out": 2
      }
    }
  },
  "protocol": {
    "driver": "GIP",
    "variant": "xboxOne",
    "mapping_flags": [
      "shareButton",
      "paddles"
    ]
  },
  "output": {
    "virtual_profile": "xboxOneS",
    "preferred_backends": [
      "driverKitHID",
      "userSpaceHID"
    ]
  }
}
```

**Ask**
I have the physical hardware and am happy to test builds, run diagnostics, share packet logs, or provide anything else needed to get this working. Let me know what would help.

## Comments

### cbandras — 2026-07-07T00:52:43Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/14#issuecomment-4898997720)

Screenshots:

<img width="4284" height="5712" alt="Image" src="https://github.com/user-attachments/assets/0e63206f-b758-4937-897a-fb2dde0e289a" />
<img width="3024" height="4032" alt="Image" src="https://github.com/user-attachments/assets/d57956f2-1e40-44f6-8cba-4a85018267c0" />

### xsyetopz — 2026-07-12T05:49:03Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/14#issuecomment-4950135827)

Interesting...

I suppose I need to iterate on the profile system to either programmatically generate them from Linux Kernel, or a community-maintained catalogue.

However, There were issues trying other ways, so, I'll see what I can feasibly do here, okey?

Okey! Thank you.

### xsyetopz — 2026-07-12T05:51:13Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/14#issuecomment-4950140390)

There's the `packet log` field. I'm thinking about trying to make this less of "Need Apple Dev account, or else not happening", if that's feasible for users trying to add new things to it.

Apple's scenery is quite complicated, even for me. I'll try my best.
