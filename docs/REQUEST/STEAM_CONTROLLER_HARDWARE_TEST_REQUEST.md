# Steam Controller Hardware Test Request

OJD has source-backed experimental Steam Controller support from Linux
`hid-steam.c`, but it must stay marked experimental until real hardware confirms
wired input, wireless receiver lifecycle, and lizard-mode timing on macOS.

## Required Test Matrix

Test both physical paths if available:

- wired Steam Controller over USB, VID `0x28de`, PID `0x1102`
- wireless Steam Controller receiver, VID `0x28de`, PID `0x1142`

For each test, record:

- macOS version
- OJD commit
- controller firmware or Steam Client state, if known
- whether Steam Client is running or fully quit
- whether the controller was already connected before OJD started
- whether Input Test shows each button/stick/trigger state correctly
- any duplicate input, stale controller, stuck button, or missed disconnect

## Build And Run

From the repository root:

```bash
brew install libusb
swift build
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
```

If testing the installed app, install or rebuild the app normally, then open the
menu-bar Input Test window. If testing only parser-visible HID bytes, use
`OpenJoystickDriverHIDTool` with the exact VID/PID below.

## Wired Controller Capture

Plug the Steam Controller directly over USB with Steam Client fully quit, then
run:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1102 --seconds 30
```

Capture one neutral packet, then one action at a time:

- A, B, X, Y pressed and released
- left bumper, right bumper pressed and released
- left grip, right grip pressed and released
- Back, Steam, Start pressed and released
- D-pad up, down, left, right pressed and released
- left stick full left, right, up, down, center
- left stick click pressed and released
- left trigger minimum, half if possible, full
- right trigger minimum, half if possible, full
- left trackpad touch without click, if possible
- left trackpad click, if possible
- right trackpad touch/click, if visible

For each labeled action, paste the `REPORT ... bytes=...` line and note what
changed in Input Test.

## Wireless Receiver Lifecycle Capture

Plug in only the wireless receiver first, with the controller powered off:

```bash
OJD_USE_LOCAL_SWIFTUSB=1 swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1142 --seconds 60
```

Then record these phases in order:

1. receiver plugged in, controller still off
2. controller powered on and connected
3. neutral state after connection
4. one simple input packet, such as A press/release
5. controller powered off or disconnected
6. one minute idle after disconnect
7. controller powered back on without restarting OJD

Paste every `REPORT ... bytes=...` line around the connect and disconnect
transitions. OJD specifically needs to verify whether the receiver emits:

- wireless lifecycle report `0x03` with connected payload `0x02`
- wireless lifecycle report `0x03` with disconnected payload `0x01`
- status fallback report `0x04` when OJD starts after the controller is already connected

Also record whether Input Test creates output only after connection, removes or
neutralizes output after disconnect, and resumes after reconnect.

## Lizard-Mode Behavior

Linux disables the Steam Controller's keyboard/mouse lizard mappings while the
input device is open and restores defaults when it closes. OJD sends the same
source-backed feature report sequence, but macOS timing still needs hardware
confirmation.

Check these states:

- before OJD opens the controller, note whether the controller moves the mouse or sends keyboard input
- while OJD Input Test is open and receiving controller input, note whether mouse/keyboard lizard behavior stops
- after OJD quits or the controller disconnects, note whether default lizard behavior returns
- repeat once with Steam Client running, if safe, and note any conflict or duplicate input

Do not mark this behavior verified unless the physical controller confirms it.

## Pass/Fail Summary To Paste Back

Use this template in the GitHub issue:

```text
OJD commit:
macOS version:
Steam Client running: yes/no
Controller path tested: wired / wireless / both

Wired 0x28de:0x1102:
- HID reports captured: yes/no
- Input Test buttons/sticks/triggers correct: yes/no, notes:
- Lizard mode disabled while open: yes/no/unknown, notes:
- Lizard mode restored after close: yes/no/unknown, notes:

Wireless receiver 0x28de:0x1142:
- Receiver-only attachment creates usable controller: yes/no
- Connect event observed: yes/no, report bytes:
- Status fallback observed when already connected: yes/no, report bytes:
- Disconnect event observed: yes/no, report bytes:
- Input gated until connect: yes/no
- Output neutralized/removed after disconnect: yes/no
- Reconnect without restarting OJD works: yes/no

Packet excerpts:
- neutral:
- A press:
- A release:
- left stick full left:
- left trigger full:
- receiver connect:
- receiver disconnect:

Unexpected behavior:
```
