# SteelSeries Nimbus Test Record

What happened when the maintainer set the player lights of a SteelSeries Nimbus over Bluetooth with OJD, once.

## Test Setup

| Item | Value |
| --- | --- |
| Controller | SteelSeries Nimbus, `0111:1420` |
| Connection | Bluetooth |
| OpenJoystickDriver | `0.6.0-alpha.4 (1.32.33)`, Release build of commit `0828f3fbd` |
| macOS | 27.2 (26B123) |
| Mac | MacBook Pro (`MacBookPro18,2`), Apple silicon |
| Handled by | macOS |

## Results

| Command | Output | Controller |
| --- | --- | --- |
| `ojd controller player 0111:1420 1` | `Sent player to Nimbus.` | Player light 1 lit |
| `ojd controller player 0111:1420 2` | `Sent player to Nimbus.` | Player light 2 lit |

## Not Tested

- Players 3 and 4.
- A guided input test of the buttons, D-pad, sticks and triggers.
- The USB Nimbus, `1038:1420`.
