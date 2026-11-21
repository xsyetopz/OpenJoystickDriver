# SteelSeries Nimbus Test Record

What happened when the maintainer set the player lights of a SteelSeries Nimbus with OJD, once over Bluetooth and once over USB.

## Test Setup

| Item | Value |
| --- | --- |
| Controller | SteelSeries Nimbus, `0111:1420` over Bluetooth, `1038:1420` over USB |
| OpenJoystickDriver | `0.6.0-alpha.4 (1.32.33)`, Release build of commit `0828f3fbd` |
| macOS | 27.2 (26B123) |
| Mac | MacBook Pro (`MacBookPro18,2`), Apple silicon |
| Handled by | macOS |

## Bluetooth Results

| Command | Output | Controller |
| --- | --- | --- |
| `ojd controller player 0111:1420 1` | `Sent player to Nimbus.` | Player light 1 lit |
| `ojd controller player 0111:1420 2` | `Sent player to Nimbus.` | Player light 2 lit |

## USB Results

The bundled `1038:1420` record has no player lights, so `ojd controller player 1038:1420 1` fails with `E2013`. The USB report descriptor has the same 1-byte output report as Bluetooth: usage page `0xFF00`, usage `0xFF03`, 4 bits. The maintainer installed a user patch that gave the USB record the Bluetooth record's player lights.

| Command | Output | Controller |
| --- | --- | --- |
| `ojd controller player 1038:1420 1` | `Sent player to Nimbus.` | Charging pattern went from 2 solid and 2 flashing lights to 3 solid and 1 flashing |
| `ojd controller player 1038:1420 2` | `Sent player to Nimbus.` | Still 3 solid and 1 flashing |

On USB the lights show the charging pattern, and the player value doesn't change them. The first change matches the charge rising, not player 1. The USB record keeps no player lights. Input Test responded to the Nimbus over USB, as reported by the maintainer.

## Not Tested

- Players 3 and 4. They use the same report as players 1 and 2.
- A Guided Check (`ojd controller check --validate`) on either connection.
- USB player lights with a fully charged battery.
