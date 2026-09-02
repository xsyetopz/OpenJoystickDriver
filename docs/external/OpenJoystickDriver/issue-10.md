# #10: xbox 360 wired controller lighted logo ring continuous flashing

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/10
- **State:** CLOSED
- **Author:** Jottle
- **Created:** 2026-06-09T18:38:23Z
- **Updated:** 2026-08-25T19:14:08Z
- **Closed:** 2026-08-25T19:14:08Z
- **Labels:** bug, help wanted

## Report

Got this driver up and running in Macos 13.7.8 with a wired xbox 360 controller.

It does work, but the lighted ring around the xbox logo in the center of the controller (which usually indicates the player number with only one solid light bar in 4 different configurations) constantly flashes when connected. Is there any way to get it to just light up solid instead of the flashing?

It's super distracting to have the controller flashing the whole time. Thanks!

## Comments

### xsyetopz — 2026-06-10T10:41:52Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4669256277)

Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.

### xsyetopz — 2026-06-10T11:12:37Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4669519753)

> Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.

Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.

### Jottle — 2026-06-11T16:09:07Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4682554806)

> > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
>
> Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.

Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.

### xsyetopz — 2026-06-11T16:20:24Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4682655615)

> > > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
> >
> >
> > Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.
>
> Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.

There will be `0.5.0-alpha.5` release soon enough, with lots of additions + fixes, && I'll try to handle this, too, so y'can test it out! One huge addition is the change of old SDL backend into actual SDL3-based upstream backend due to new Issue report on SDL changes that allowed 3rd-party controllers to be used thru libusb, which was not a thing previously.

So, it could be a resolve, hopefully. We'll see...

### xsyetopz — 2026-06-11T17:50:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4683395393)

> > > > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
> > >
> > >
> > > Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.
> >
> >
> > Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.
>
> There will be `0.5.0-alpha.5` release soon enough, with lots of additions + fixes, && I'll try to handle this, too, so y'can test it out! One huge addition is the change of old SDL backend into actual SDL3-based upstream backend due to new Issue report on SDL changes that allowed 3rd-party controllers to be used thru libusb, which was not a thing previously.
>
> So, it could be a resolve, hopefully. We'll see...

Here's [0.5.0-alpha.5](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.5) for y'to test.

### Jottle — 2026-06-11T18:19:50Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4683658231)

> > > > > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
> > > >
> > > >
> > > > Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.
> > >
> > >
> > > Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.
> >
> >
> > There will be `0.5.0-alpha.5` release soon enough, with lots of additions + fixes, && I'll try to handle this, too, so y'can test it out! One huge addition is the change of old SDL backend into actual SDL3-based upstream backend due to new Issue report on SDL changes that allowed 3rd-party controllers to be used thru libusb, which was not a thing previously.
> > So, it could be a resolve, hopefully. We'll see...
>
> Here's [0.5.0-alpha.5](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.5) for y'to test.

alpha .5 now looking good in the input tester. L1 and R1 still show as blank buttons, but all of the other pads, buttons, and triggers register correctly now. Anything else you want me to test? I still haven't used it in-game yet.

### xsyetopz — 2026-06-11T18:20:47Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4683665681)

> > > > > > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
> > > > >
> > > > >
> > > > > Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.
> > > >
> > > >
> > > > Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.
> > >
> > >
> > > There will be `0.5.0-alpha.5` release soon enough, with lots of additions + fixes, && I'll try to handle this, too, so y'can test it out! One huge addition is the change of old SDL backend into actual SDL3-based upstream backend due to new Issue report on SDL changes that allowed 3rd-party controllers to be used thru libusb, which was not a thing previously.
> > > So, it could be a resolve, hopefully. We'll see...
> >
> >
> > Here's [0.5.0-alpha.5](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.5) for y'to test.
>
> alpha .5 now looking good in the input tester. L1 and R1 still show as blank buttons, but all of the other pads, buttons, and triggers register correctly now. Anything else you want me to test? I still haven't used it in-game yet.

I'll send a new patch for this issue, then report back with `alpha.6`, okay?

### xsyetopz — 2026-06-11T18:42:06Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4683826181)

> > > > > > > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
> > > > > >
> > > > > >
> > > > > > Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.
> > > > >
> > > > >
> > > > > Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.
> > > >
> > > >
> > > > There will be `0.5.0-alpha.5` release soon enough, with lots of additions + fixes, && I'll try to handle this, too, so y'can test it out! One huge addition is the change of old SDL backend into actual SDL3-based upstream backend due to new Issue report on SDL changes that allowed 3rd-party controllers to be used thru libusb, which was not a thing previously.
> > > > So, it could be a resolve, hopefully. We'll see...
> > >
> > >
> > > Here's [0.5.0-alpha.5](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.5) for y'to test.
> >
> >
> > alpha .5 now looking good in the input tester. L1 and R1 still show as blank buttons, but all of the other pads, buttons, and triggers register correctly now. Anything else you want me to test? I still haven't used it in-game yet.
>
> I'll send a new patch for this issue, then report back with `alpha.6`, okay?

Here's [0.5.0-alpha.6](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.6) for y'to try out now. Lemme know if changes worked.

### Jottle — 2026-06-11T18:45:59Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4683859294)

Confirmed. alpha .6 input tester now shows all buttons as mapped and registering correctly.

### Jottle — 2026-06-12T18:20:18Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4694062392)

I know this issue is now closed out, but I've done some more testing with the wired 360 controller, and I'm seeing some weird detection issues with steam. In non-steam games (some through the epic game store) that natively support the xbox 360 controller, those games seem to mostly work just fine with the "xbox 360 HID" compatibility identity selected.

But when I open steam with the "xbox 360 HID" identity selected in openjoystick, steam sees the 360 controller as a Logitech Astro C40 TR controller. And even weirder, it sees it as two separate controllers connected (see screenshot). None of the button presses register correctly in this configuration. So it obviously doesn't work correctly with this configuration.

Choosing the "Generic HID" profile makes Steam detect the controller as "OpenJoystickDriver Generic HID Gamepad" and in "SDL 2/3" identity, it comes up as "OpenJoystickDriver Virtual Gamepad." In both of those other cases, it shows two gamepads connected, and steam doesn't recognize any of the button presses on the gamepad in the built in steam controller setup/tester.

So something weird is still going on within steam at least.

<img width="652" height="335" alt="Image" src="https://github.com/user-attachments/assets/10e880da-7517-48d2-825c-f90e56f1e5a4" />

<img width="633" height="315" alt="Image" src="https://github.com/user-attachments/assets/49c69345-4d80-4f32-997d-5a4fa2055827" />

<img width="634" height="348" alt="Image" src="https://github.com/user-attachments/assets/5d299c8f-e32e-4e5c-9802-720a02e8fc47" />

### Jottle — 2026-06-12T18:22:00Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4694073603)

> I know this issue is now closed out, but I've done some more testing with the wired 360 controller, and I'm seeing some weird detection issues with steam. In non-steam games (some through the epic game store) that natively support the xbox 360 controller, those games seem to mostly work just fine with the "xbox 360 HID" compatibility identity selected.
>
> But when I open steam with the "xbox 360 HID" identity selected in openjoystick, steam sees the 360 controller as a Logitech Astro C40 TR controller. And even weirder, it sees it as two separate controllers connected (see screenshot). None of the button presses register correctly in this configuration. So it obviously doesn't work correctly with this configuration.
>
> Choosing the "Generic HID" profile makes Steam detect the controller as "OpenJoystickDriver Generic HID Gamepad" and in "SDL 2/3" identity, it comes up as "OpenJoystickDriver Virtual Gamepad." In both of those other cases, it shows two gamepads connected, and steam doesn't recognize any of the button presses on the gamepad in the built in steam controller setup/tester.
>
> So something weird is still going on within steam at least.
> <img alt="Image" width="652" height="335" src="https://private-user-images.githubusercontent.com/6255618/607297120-10e880da-7517-48d2-825c-f90e56f1e5a4.jpg"> <img alt="Image" width="633" height="315" src="https://private-user-images.githubusercontent.com/6255618/607297524-49c69345-4d80-4f32-997d-5a4fa2055827.jpg"> <img alt="Image" width="634" height="348" src="https://private-user-images.githubusercontent.com/6255618/607297850-5d299c8f-e32e-4e5c-9802-720a02e8fc47.jpg">



> > > > > > > > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
> > > > > > >
> > > > > > >
> > > > > > > Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.
> > > > > >
> > > > > >
> > > > > > Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.
> > > > >
> > > > >
> > > > > There will be `0.5.0-alpha.5` release soon enough, with lots of additions + fixes, && I'll try to handle this, too, so y'can test it out! One huge addition is the change of old SDL backend into actual SDL3-based upstream backend due to new Issue report on SDL changes that allowed 3rd-party controllers to be used thru libusb, which was not a thing previously.
> > > > > So, it could be a resolve, hopefully. We'll see...
> > > >
> > > >
> > > > Here's [0.5.0-alpha.5](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.5) for y'to test.
> > >
> > >
> > > alpha .5 now looking good in the input tester. L1 and R1 still show as blank buttons, but all of the other pads, buttons, and triggers register correctly now. Anything else you want me to test? I still haven't used it in-game yet.
> >
> >
> > I'll send a new patch for this issue, then report back with `alpha.6`, okay?
>
> Here's [0.5.0-alpha.6](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.6) for y'to try out now. Lemme know if changes worked.

### xsyetopz — 2026-06-12T20:10:38Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4694933939)

> > I know this issue is now closed out, but I've done some more testing with the wired 360 controller, and I'm seeing some weird detection issues with steam. In non-steam games (some through the epic game store) that natively support the xbox 360 controller, those games seem to mostly work just fine with the "xbox 360 HID" compatibility identity selected.
> > But when I open steam with the "xbox 360 HID" identity selected in openjoystick, steam sees the 360 controller as a Logitech Astro C40 TR controller. And even weirder, it sees it as two separate controllers connected (see screenshot). None of the button presses register correctly in this configuration. So it obviously doesn't work correctly with this configuration.
> > Choosing the "Generic HID" profile makes Steam detect the controller as "OpenJoystickDriver Generic HID Gamepad" and in "SDL 2/3" identity, it comes up as "OpenJoystickDriver Virtual Gamepad." In both of those other cases, it shows two gamepads connected, and steam doesn't recognize any of the button presses on the gamepad in the built in steam controller setup/tester.
> > So something weird is still going on within steam at least.
> > <img alt="Image" width="652" height="335" src="https://private-user-images.githubusercontent.com/6255618/607297120-10e880da-7517-48d2-825c-f90e56f1e5a4.jpg"> <img alt="Image" width="633" height="315" src="https://private-user-images.githubusercontent.com/6255618/607297524-49c69345-4d80-4f32-997d-5a4fa2055827.jpg"> <img alt="Image" width="634" height="348" src="https://private-user-images.githubusercontent.com/6255618/607297850-5d299c8f-e32e-4e5c-9802-720a02e8fc47.jpg">
>
> > > > > > > > > Hey! I'll see what I can do for the 4th Alpha of upcoming `0.5.0` release. I'll update my comment once I get a new release binary going that requires your testing.
> > > > > > > >
> > > > > > > >
> > > > > > > > Try [0.5.0-alpha.4](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.4) that attempted a possible solution. Needs your testing since y'own a physical wired variant.
> > > > > > >
> > > > > > >
> > > > > > > Confirmed that the bug is fixed! The center button lights up correctly with an oem wired xbox 360 controller. However, when using the xbox 360 HID compatibility identity, the input tester doesn't map the buttons correctly. For example R1 and L1 are mapping to "A" and "B" respectively. "X" maps to the "home" button, and "A" and "B" map to blank icons in the tester. Not sure if that's just a tester but and they work fine in-game. Will have to verify soon.
> > > > > >
> > > > > >
> > > > > > There will be `0.5.0-alpha.5` release soon enough, with lots of additions + fixes, && I'll try to handle this, too, so y'can test it out! One huge addition is the change of old SDL backend into actual SDL3-based upstream backend due to new Issue report on SDL changes that allowed 3rd-party controllers to be used thru libusb, which was not a thing previously.
> > > > > > So, it could be a resolve, hopefully. We'll see...
> > > > >
> > > > >
> > > > > Here's [0.5.0-alpha.5](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.5) for y'to test.
> > > >
> > > >
> > > > alpha .5 now looking good in the input tester. L1 and R1 still show as blank buttons, but all of the other pads, buttons, and triggers register correctly now. Anything else you want me to test? I still haven't used it in-game yet.
> > >
> > >
> > > I'll send a new patch for this issue, then report back with `alpha.6`, okay?
> >
> >
> > Here's [0.5.0-alpha.6](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.6) for y'to try out now. Lemme know if changes worked.

Xbox 360 HID being the Astro is because it's the first one I tried that actually recognises rumble outside of the built-in Input Test (e.g, PCSX2), that the stock Xbox 360 Wired/Wireless did not (no idea why). It's called "Compatibility" for a reason, as Xbox 360 HID naturally binds to the closest XInput device that has all the capabilities present.

Y'can see my actual issue in this [SDL3 issue #15663](https://github.com/libsdl-org/SDL/issues/15663) that seems to be a workaround for.

I'll look into this new regression.

### xsyetopz — 2026-06-13T13:47:43Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4698701632)

Try [0.5.0-alpha.7](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.7) && tell me if that's good now. I had to revert *some* alpha.5 changes as they broke a few SDL-related things.

### Jottle — 2026-06-16T17:59:04Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4721760878)

> Try [0.5.0-alpha.7](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.7) && tell me if that's good now. I had to revert _some_ alpha.5 changes as they broke a few SDL-related things.

Unfortunately the button mapping is incorrect again. It reads "x" and "a" as "home" and "LB." "LB" and "RB" read as "A" and "B," respectively. And now Steam doesn't recognize the wired 360 controller no matter what compatibility profile I select.

### xsyetopz — 2026-06-16T21:58:01Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4723987696)

> > Try [0.5.0-alpha.7](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.7) && tell me if that's good now. I had to revert _some_ alpha.5 changes as they broke a few SDL-related things.
>
> Unfortunately the button mapping is incorrect again. It reads "x" and "a" as "home" and "LB." "LB" and "RB" read as "A" and "B," respectively. And now Steam doesn't recognize the wired 360 controller no matter what compatibility profile I select.

Alright, time to revert a couple versions && go back to drawing board...

### Jottle — 2026-07-09T18:44:37Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4928430210)

> > > Try [0.5.0-alpha.7](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.7) && tell me if that's good now. I had to revert _some_ alpha.5 changes as they broke a few SDL-related things.
> >
> >
> > Unfortunately the button mapping is incorrect again. It reads "x" and "a" as "home" and "LB." "LB" and "RB" read as "A" and "B," respectively. And now Steam doesn't recognize the wired 360 controller no matter what compatibility profile I select.
>
> Alright, time to revert a couple versions && go back to drawing board...

Any luck with the new alpha?

### xsyetopz — 2026-07-09T20:46:15Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-4929373928)

> > > > Try [0.5.0-alpha.7](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-alpha.7) && tell me if that's good now. I had to revert _some_ alpha.5 changes as they broke a few SDL-related things.
> > >
> > >
> > > Unfortunately the button mapping is incorrect again. It reads "x" and "a" as "home" and "LB." "LB" and "RB" read as "A" and "B," respectively. And now Steam doesn't recognize the wired 360 controller no matter what compatibility profile I select.
> >
> >
> > Alright, time to revert a couple versions && go back to drawing board...
>
> Any luck with the new alpha?

Stale. I've been doing other things && waiting for a few people to report back on previous things first. Seems like we're on a stale so far.

### xsyetopz — 2026-08-25T16:21:59Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-5413409729)

Try [0.5.0-beta.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1) and tell me if it works!

### Jottle — 2026-08-25T16:52:25Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-5413764731)

> Try [0.5.0-beta.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1) and tell me if it works!

Love the new interface, but I can't find the input testing anymore, for testing purposes. So far, it looks like it works (console verifies correct wired 360 controller, and light ring lights up correctly).

Where did the button tester go? I tried testing the face buttons: d-pad, start, select, and ABXY in a game, and they did work correctly!

Also note, it looks like the "delete" profile button doesn't do anything.

### xsyetopz — 2026-08-25T17:14:05Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-5414025172)

> Where did the button tester go? I tried testing the face buttons: d-pad, start, select, and ABXY in a game, and they did work correctly!

The input tester was kind of a hassle to keep from the old one, and I couldn't figure out a decently clean UI for it. I usually use live games/apps to test inputs on.

> Also note, it looks like the "delete" profile button doesn't do anything.

Noted.

### xsyetopz — 2026-08-25T17:14:57Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-5414034987)

If everything is resolved with the issue itself, I may close this issue?

### Jottle — 2026-08-25T18:35:49Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/10#issuecomment-5414987100)

> If everything is resolved with the issue itself, I may close this issue?

I wasn't able to test ruble, but I'm pretty sure all the other inputs are working correctly! Thanks so much. I'll report back if I find anything else.
