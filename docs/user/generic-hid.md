# Generic HID fallback

Unknown HID gamepads use parsed IOKit elements instead of guessed byte offsets. Known records keep their protocol-specific raw parsers.

Generic HID maps button usages 1 through 19, X/Y and Rx/Ry stick pairs, Z/Rz triggers, and an eight-position hat. Logical ranges are clamped and normalized. Repeated button values do not emit duplicate transitions. An invalid hat value becomes neutral.

The sixteenth virtual button carries the first extra generic button. Further buttons remain visible in OJD diagnostics but do not fit the 16-button compatibility reports.

A HID descriptor names fields but does not define a universal physical button order. Vendor reports, unusual axes, handshakes, paddles, and extra controls need a record and parser. Verify every control in Input Test or the headless input diagnostic before claiming support.
