# Wired Switch input-only pads

Many licensed wired Switch pads send one fixed HID input report and do not accept the Switch Pro Controller subcommands. SDL lists them as `SwitchInputOnlyController`. The catalog imports them from SDL's `controller_list.h` as `nintendo.switch1` records with the `input-only` quirk, which selects `SwitchInputOnlyDriver`:

| Controller | VID:PID |
| --- | --- |
| HORIPAD for Nintendo Switch | `0f0d:00c1` |
| HORI Pokken Tournament DX Pro Pad | `0f0d:0092` |
| HORI Real Arcade Pro V Hayabusa (Switch mode) | `0f0d:00aa` |
| HORI Taiko Controller for Switch | `0f0d:00f0` |
| PDP Faceoff Wired Pro Controller | `0e6f:0180` |
| PDP Faceoff Deluxe Wired Pro Controller | `0e6f:0181` |
| PDP Faceoff Wired Deluxe+ Audio Controller | `0e6f:0184` |
| PDP Wired Fight Pad Pro | `0e6f:0185` |
| PDP Rock Candy Wired Controller | `0e6f:0187` |
| PDP Afterglow Wired Deluxe+ Audio Controller | `0e6f:0188` |
| PowerA Wired Controller Plus / GameCube style | `20d6:a711` |
| PowerA Fusion Fight Pad | `20d6:a712` |
| PowerA Super Mario Controller | `20d6:a713` |
| PowerA Spectra Controller | `20d6:a714` |
| PowerA Fusion Wireless Arcade Stick (USB mode) | `20d6:a715` |
| PowerA Fusion Pro Controller (USB mode) | `20d6:a716` |
| PowerA Nano Wired Controller | `20d6:a718` |
| ZUIKI MasCon | `33dd:0001`, `33dd:0002`, `33dd:0003` |

The names come from SDL's comments. None of these pads is checked on hardware with OJD.

## Report layout

The report has no report ID. The driver reads the first 7 bytes, the layout of SDL's `SwitchInputOnlyControllerStatePacket_t`.

| Offset | Contents |
| --- | --- |
| 0 | `0x01` Y, `0x02` B, `0x04` A, `0x08` X, `0x10` L, `0x20` R, `0x40` ZL, `0x80` ZR |
| 1 | `0x01` Minus, `0x02` Plus, `0x04` left stick click, `0x08` right stick click, `0x10` Home, `0x20` Capture |
| 2 | Hat: 0–7 clockwise from up; any other value is neutral |
| 3, 4 | Left stick X, Y; unsigned, center `0x80`, up and left low |
| 5, 6 | Right stick X, Y; same encoding |

Face buttons map by position: B is south, A east, Y west, X north. ZL and ZR are digital.

## Not supported

- Rumble, player lights and motion. The pads take no Switch output reports, and SDL sends them none.
- The Taiko drum and the MasCon lever have no dedicated controls. They report through the same bits as a pad, as SDL decodes them.

## Procedure

Connect the pad over USB, then confirm the route (`ojd` is the [command-line tool](../../docs/command-line/using-the-command-line.md), and `<controller>` is an ID from the list or its `VVVV:PPPP`):

```bash
ojd controller list
ojd controller show <controller>
```

`show` should report the protocol `nintendo.switch1`, and `ojd controller show <controller> --json` should list the quirk `input-only`. Then watch the controls:

```bash
ojd controller watch <controller>
```

Push each stick fully right and fully up and confirm positive X and negative Y. Press every button, D-pad direction, Home and Capture, and confirm that the reported control matches the button position. Report the result in a new issue with the pad's VID:PID.
