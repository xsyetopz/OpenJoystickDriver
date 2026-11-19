# Wired Switch Input-Only Pads

Many licensed wired Switch pads are simple: they send one fixed HID input report and ignore the extra commands a Switch Pro Controller understands. SDL calls them `SwitchInputOnlyController`. OJD's catalog imports them from SDL's `controller_list.h` as `NintendoSwitchInputOnly` records:

| Controller | VID:PID |
| --- | --- |
| HORIPAD for Nintendo Switch | 0f0d:00c1 |
| HORI Pokken Tournament DX Pro Pad | 0f0d:0092 |
| HORI Real Arcade Pro V Hayabusa (Switch mode) | 0f0d:00aa |
| HORI Taiko Controller for Switch | 0f0d:00f0 |
| PDP Faceoff Wired Pro Controller | 0e6f:0180 |
| PDP Faceoff Deluxe Wired Pro Controller | 0e6f:0181 |
| PDP Faceoff Wired Deluxe+ Audio Controller | 0e6f:0184 |
| PDP Wired Fight Pad Pro | 0e6f:0185 |
| PDP Rock Candy Wired Controller | 0e6f:0187 |
| PDP Afterglow Wired Deluxe+ Audio Controller | 0e6f:0188 |
| PowerA Wired Controller Plus / GameCube style | 20d6:a711 |
| PowerA Fusion Fight Pad | 20d6:a712 |
| PowerA Super Mario Controller | 20d6:a713 |
| PowerA Spectra Controller | 20d6:a714 |
| PowerA Fusion Wireless Arcade Stick (USB mode) | 20d6:a715 |
| PowerA Fusion Pro Controller (USB mode) | 20d6:a716 |
| PowerA Nano Wired Controller | 20d6:a718 |
| ZUIKI MasCon | 33dd:0001, 33dd:0002, 33dd:0003 |

The names come from SDL's comments. Nobody has checked any of these pads on hardware.

## Report Layout

The report has no ID byte. The driver reads the first 7 bytes (SDL's `SwitchInputOnlyControllerStatePacket_t`).

| Offset | Contents |
| --- | --- |
| 0 | 0x01 Y, 0x02 B, 0x04 A, 0x08 X, 0x10 L, 0x20 R, 0x40 ZL, 0x80 ZR |
| 1 | 0x01 Minus, 0x02 Plus, 0x04 left stick click, 0x08 right stick click, 0x10 Home, 0x20 Capture |
| 2 | D-pad (hat): 0 to 7, going clockwise from up. Any other value means not pressed |
| 3, 4 | Left stick X, Y. No sign, center 0x80, up and left are low |
| 5, 6 | Right stick X, Y, read the same way |

Face buttons map by where they sit (B bottom, A right, Y left, X top). ZL and ZR are on or off, with no in-between.

## What Doesn't Work

- Rumble, player lights, and motion: these pads don't take Switch output reports.
- The Taiko drum and the MasCon lever have no controls of their own. They send the same bits as a normal pad.

## Steps

1. Connect the pad over USB.
2. Check how OJD connected it (`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or `VVVV:PPPP`). `show` should report NintendoSwitchInputOnly.

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. Push each stick fully right, then fully up. Right should give a positive X, and up a negative Y.
5. Press every button, every D-pad direction, Home, and Capture. Check that each one matches.
6. Report in an issue with the pad's VID:PID.
