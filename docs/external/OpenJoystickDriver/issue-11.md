# #11: Logitech F310 (Xinput mode) button mapping wrong

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/11
- **State:** OPEN
- **Author:** qwertychouskie
- **Created:** 2026-06-11T01:24:28Z
- **Updated:** 2026-07-18T22:25:30Z
- **Closed:** —
- **Labels:** bug, help wanted

## Report

When using the built-in gamepad tester, a Logitech F310 in Xinput mode works, but a lot of the buttons are mis-mapped.  This controller works as expected with SDL3's `testcontroller` program.  Note: using this controller in Xinput mode requires SDL3 built from the latest Git, as out-of-the-box support for controllers that require libusb on macOS was just merged a few hours ago (see https://github.com/libsdl-org/SDL/pull/15794).

Now that I think about it, overall, now that SDL3 supports controllers that require libusb on macOS out-of-the-box, maybe OpenJoystickDriver could use SDL3 to access the real gamepad(s)?  That would probably both be easier to maintain, and give better results across a wide variety of gamepads.

## Comments

### xsyetopz — 2026-06-11T11:02:51Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/11#issuecomment-4679854680)

> When using the built-in gamepad tester, a Logitech F310 in Xinput mode works, but a lot of the buttons are mis-mapped. This controller works as expected with SDL3's `testcontroller` program. Note: using this controller in Xinput mode requires SDL3 built from the latest Git, as out-of-the-box support for controllers that require libusb on macOS was just merged a few hours ago (see [libsdl-org/SDL#15794](https://github.com/libsdl-org/SDL/pull/15794)).
>
> Now that I think about it, overall, now that SDL3 supports controllers that require libusb on macOS out-of-the-box, maybe OpenJoystickDriver could use SDL3 to access the real gamepad(s)? That would probably both be easier to maintain, and give better results across a wide variety of gamepads.

I'll look into this! Thanks for your first issue. It's very helpful that people test my programme out when I lack the physical devices to find further edge cases like this.
