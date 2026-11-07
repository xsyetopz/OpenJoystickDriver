---
paths:
  - "**/*"
---

# hardware_tick_without_capture

A hardware task is ticked with a capture from that hardware. Without one, it stays unticked and is reported as hardware-gated.

```text
tasks.md:40:3: error: ticked with no capture [hardware_tick_without_capture]
- [x] T3 Capture the 310B report over Bluetooth LE.
  ^
```
