## Context

`XUSBDriver` serves wired Xbox 360 pads (`FF/5D/01`) and one slot of the wireless receiver (`FF/5D/81`, `045e:0291`, `0719`, `02a9`). This change is planning only: it holds specs and tasks, no code.
Sources read for this plan: the code at the paths below; Linux `drivers/input/joystick/xpad.c` from `torvalds/linux` master (read 2026-10-25); `paroj/xpad` issue 119 and commits `52cb159` and `3470f9f` through the GitHub API (read 2026-10-25); the maintainer's notes on `zeromiyi/x360w` (MIT, tested on macOS 26.5.2 with `045e:0719`), which were not re-read for this plan.
Hardware is not in hand for this plan. Every behavior that needs a receiver or a clone is a task gated on a check in "Hardware Checks (Maintainer)". Testers receive tester builds (`docs/development/tester-builds.md`).

## Research claims checked against the code

| Claim | Verdict | Evidence |
| --- | --- | --- |
| No power-off packet exists. | Confirmed. | `XUSBDriver.swift` has no `C0` output besides the inquiry and rumble; `DevicePipeline+USBSession.swift:72` sends only a record's `shutdown` list, and `xbox-xusb.json` has none. |
| xpad powers off "on session close". | Corrected. | xpad sends `00 00 08 C0 ...` (12 bytes) in `xpad360w_poweroff_controller` only (a) in `xpad_suspend` when the module parameter `auto_poweroff` (default true) is set and a pad is present, and (b) after the mode button is held for `XPAD360W_POWEROFF_TIMEOUT` (5) seconds, checked when the next pad packet is processed. It does not send it when the driver unbinds. x360w sends none. A power-off on every OJD close has no upstream precedent and is gated on hardware. |
| The inquiry is sent before the IN read is armed, so the reply can be lost. | Half confirmed, half dropped. | Order confirmed: `performUSBHandshake` (startup writes) runs before `runUSBInputLoop` (`DevicePipeline+USBStartup.swift`, `DevicePipeline+USBInputLoop.swift:12`), and xpad's `xpad360w_start_input` submits the IN URB first. "Can be lost" has no evidence: x360w sends the inquiry before it starts its read thread and works on hardware, and the comment at `XUSBDriver.swift:57-60` states the loss without a capture. The loss claim is dropped; check H2 decides. |
| The heuristic only reacts to pad data, so an idle pad never recovers. | Confirmed by code. | `decode` returns the inquiry resend only inside the `data[1] == 0x01` branch (`XUSBDriver.swift:259-264`); `DevicePipeline+USBInputLoop.swift:41` drains pending writes only after a successful read, so an idle slot (read timeouts) sends none. |
| A time-based resend is the fix. | Replaced. | x360w treats any valid pad report as presence at once, so no resend is needed when the pad talks. The resend remains a fallback for an idle connected pad if H2 fails. A time-based resend also needs a keep-alive channel; the XUSB plan has none unless a rumble template names a resend interval (`PhysicalProtocolDriver.swift:182-191`). |
| `0291` is a clone receiver. | Corrected. | `0291` is an original, `0719` a later original, `02a9` a clone (x360w notes). All three records exist with `XboxXUSB:Receiver`. |
| Battery, chatpad and headset are missing and xpad has them. | Dropped. | Unconfirmed: the fetch was truncated, and x360w has no battery either. The headset presence bit (byte 1, `0x40`) is out of scope. |
| Interface-to-slot mapping was not read. | Read here. | `roleProfiles` (`ProtocolDriverRegistry+InterfaceContract.swift:22-62`) keeps interfaces with alternate setting 0 that pass the contract, sorts by interface number, and uses the index as the slot ordinal (at most four). x360w uses descriptor order. Both agree when the descriptor lists ascending numbers; a capture decides (H6). The doc comment at `InterfaceContract.swift:4` says `XUSBDriver` lights players 1 to 4, but `XUSBDriver.swift:217` says the manager assigns the LED; the comment is corrected by task 5.3. |
| The wired variant has no init write; xpad issue 119 covers ShanWan clones. | Corrected. | Issue 119 is a Fantech GP11 Shooter report; ShanWan (`045e:028e`, manufacturer `SHANWAN`) and a Trust GXT 540 Yula appear later in the thread. Commit `52cb159` sends the sequence to every `XTYPE_XBOX360` pad and "breaks" issue 171 (Logitech F710). Commit `3470f9f` limits it to a quirk flag (Gamesir-G3w `05ac:055b`) or a manufacturer string equal to "shanwan" without regard to case. Neither commit is in `torvalds/linux` master: a search of the fetched `xpad.c` finds no `QUIRK_360` and no `shanwan`. |
| No sleep/wake handling. | Corrected. | `DeviceManager.systemWillSleep` tears down every session as an unplug (`DeviceManager+Lifecycle.swift:60-69`), which runs the pipeline stop and its shutdown writes; wake re-detects. The manager path is tested (`StartupLifetimeTests+SleepTeardown`); a receiver slot is not. |
| 360Controller forks panic on sleep with a wireless receiver. | Dropped. | Second-hand, about a kernel extension; OJD runs in user space through IOUSBHost. H7 tests the real behavior. |
| Steam holding the receiver needs a name instead of a silent retry. | Corrected. | OJD does not retry silently: an open refused with an exclusive owner reports `ownedByAnotherClient`, logs the holder, and waits for the release notification (`DevicePipeline+USBStartup.swift:61-92`). A test pins the user-visible state; no new retry is added. |

## Decisions

### D1 Presence

A receiver slot is connected when a presence report says so (`byte0 & 0x08` and `byte1 & 0x80`) or when a pad report decodes (`byte1 == 0x01`, length at least 24, inner type `0x00`, inner length byte `0x14`). The pad report that proves presence is decoded in the same call, so no input is lost. The resend heuristic, `padReportsWithoutPresence`, `resendPresenceInquiry` and the `receiverInquiryResendLimit` datum of `xbox-xusb.json` are removed; no other reader of the datum exists for XUSB. `presenceResendReports` stays a tuning key because `xbox-gip.json` and `GIPDriver.swift` read it; only the XUSB entry in `rawUSBTuningKeys` goes.
If H2 shows that an idle connected pad stays unseen, the fallback is one named datum, `presenceInquiryIntervalMilliseconds`, which gives the receiver plan a keep-alive that resends the inquiry for a slot that is not connected. It is not built before H2 fails.

### D2 Power-off

`ReceiverPowerOffOnClose`: the bytes `00 00 08 C0 00 00 00 00 00 00 00 00` are family data in `xbox-xusb.json` (a controller-specific byte sequence outside an algorithm belongs in data). The protocol-description schema and loader gain a `defaults.receiverPowerOff` packet limited by `variants`, read by the XUSB family. It is not a `session.shutdown` entry, because `invalidateUSBHandle` sends the shutdown list on I/O errors and unplug too (`DevicePipeline+USBInputLoop.swift:233`).
The write is sent only on a deliberate close: the pipeline stop, which system sleep also runs, and only for a slot whose controller is connected. It is not sent from `invalidateUSBHandle` (`DevicePipeline+USBInputLoop.swift:233`), which handles I/O errors and unplug, because a transient error must not turn a pad off. A driver hook `powerOffWrites()` reads `receiverPowerOff` and is called by the stop path only; `sendUSBShutdownWrites` never sees it, and the record `shutdown` list keeps its meaning.
Default: the datum is absent from `xbox-xusb.json` until H4 and H5 pass; the code and tests land first. Decision of the maintainer after H4/H5: ship on, ship off, or make it a named tuning key `powerOffOnClose`. It is never silent: when it ships on, the Controllers detail and the wiki say that closing OJD turns a wireless pad off.

### D3 Guide hold

`GuideHoldPowerOff`: holding Guide (button word bit 10) for 5 s sends the same packet, as in xpad. Linux evaluates the hold only when the next pad packet arrives, so a held button with no further packets never fires. H5 records whether the pad repeats reports while Guide is held; if it does not, the driver needs a timer, which needs the keep-alive channel of D1's fallback. The hold seconds is a tuning value (`guideHoldPowerOffSeconds`, 0 turns it off) because a profile may use a Guide long hold.

### D4 Wired clone start sequence

Data, not code. Three vendor control reads from `3470f9f`, sent before any input read, results discarded, 100 ms timeout:

| # | `bmRequestType` | `bRequest` | `wValue` | `wIndex` | `wLength` |
| --- | --- | --- | --- | --- | --- |
| 1 | `0xC1` | `0x01` | `0x0100` | `0x0000` | 20 |
| 2 | `0xC1` | `0x01` | `0x0000` | `0x0000` | 8 |
| 3 | `0xC0` | `0x01` | `0x0000` | `0x0000` | 4 |

OJD already has this shape: a record mode's `session.control` takes vendor transfers with a `match` gate (`manufacturer`, `product`, `bcdDevice`); `ControllerSession.swift:48-135`, validated at `ControllerRecordDocument+Session.swift:178-250`; request types `0xC0` and `0xC1` and lengths up to 64 are accepted. `performUSBHandshake` runs control transfers before the startup output and before the input loop.
The gate compares the manufacturer string exactly, while xpad ignores case. The observed string is `SHANWAN`; H8 records the exact bytes of each clone. A clone with another spelling gets its own gate entry, not a looser rule.
The transfers apply to the shared model `045e:028e` through a controller patch (`Resources/ControllerPatches/045e/`), gated so genuine pads and the F710 class (issue 171) never receive them. Sending the sequence to a pad that does not need it is the failure issue 171 shows. `05ac:055b` (Gamesir-G3w) has no record in the catalog; adding one is a separate hardware-backed decision (H8).

### D5 Licenses

OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license, so GPL and AGPL code cannot be ported. Linux `xpad.c` (GPL-2.0-or-later) and `paroj/xpad` supply facts only: byte values, request fields, sequence order and observed behavior. All code is written independently from those facts. Code from `zeromiyi/x360w` (MIT) may be used with its copyright notice and license text kept in `THIRD_PARTY_NOTICES.md`; code from SDL (zlib) likewise. `docs/development/compatibility-sources.md` keeps stating that no Linux code is copied.

## Risks

- A power-off on close surprises a user who restarts the service to apply a setting. Mitigation: D2 gating, and the stop path distinguishes a restart only if H4 shows it matters.
- Input-implies-presence could show a slot as connected from a stale packet. H1 checks pad removal ordering.
- The control reads reach a genuine pad if the gate is wrong. The gate test uses a genuine-pad string set.

## Open Questions

- Does the system wait for the stop to finish before sleeping? `SystemPowerNotificationObserver` must delay the sleep acknowledgement until `systemWillSleep` returns, or the write may never leave. Task 3.4 reads it; H7 confirms.
- Ship `ReceiverPowerOffOnClose` on, off, or as a setting: after H4/H5.
