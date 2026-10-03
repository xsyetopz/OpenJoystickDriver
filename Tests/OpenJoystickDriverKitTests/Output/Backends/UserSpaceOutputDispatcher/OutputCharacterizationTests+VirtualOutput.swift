import Testing

@testable import OpenJoystickDriverKit

// Pinned virtual-output-path transcripts; the rendering rules are on `OutputCharacterizationTests`.
extension OutputCharacterizationTests {
  /// Family labels reach the bits by parser label, not by control: PlayStation Share (Create) and
  /// Nintendo Capture land on bit 15 like standard Share, standard View (Back) on bit 9.
  @Test
  func familyLabelsReachTheirBits() async {
    var lines: [String] = []
    // Each family's former parser button name and the control it now reports under its labels.
    let families: [(String, DeviceIdentifier, [(String, ControlID)])] = [
      (
        "ps", Self.playStation,
        [
          ("share", .view), ("options", .menu), ("ps", .guide), ("cross", .faceSouth),
          ("touchpad", .touchpadClick), ("mute", .microphone),
        ]
      ),
      (
        "std", Self.standard,
        [
          ("back", .view), ("start", .menu), ("guide", .guide), ("a", .faceSouth),
          ("share", .share),
        ]
      ),
      (
        "nin", Self.nintendo,
        [
          ("share", .capture), ("back", .view), ("start", .menu), ("guide", .guide),
          ("b", .faceEast),
        ]
      ),
    ]
    for (family, identifier, buttons) in families {
      let output = VirtualOutput()
      for (button, control) in buttons {
        await output.dispatch([.press(control)], from: identifier)
        lines += output.render("\(family) +\(button)")
        await output.dispatch([.release(control)], from: identifier)
        lines += output.render("\(family) -\(button)")
      }
    }
    #expect(
      lines == [
        "ps +share b=8000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0080000000000000000000000000",
        "ps -share b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "ps +options b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 8000000000000000000000000000",
        "ps -options b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "ps +ps b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "ps -ps b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "ps +cross b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0100000000000000000000000000",
        "ps -cross b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "ps +touchpad b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "ps -touchpad b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "ps +mute b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "ps -mute b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "std +back b=0200 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 4000000000000000000000000000",
        "std -back b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "std +start b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 8000000000000000000000000000",
        "std -start b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "std +guide b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "std -guide b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "std +a b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0100000000000000000000000000",
        "std -a b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "std +share b=8000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0080000000000000000000000000",
        "std -share b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "nin +share b=8000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0080000000000000000000000000",
        "nin -share b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "nin +back b=0200 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 4000000000000000000000000000",
        "nin -back b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "nin +start b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 8000000000000000000000000000",
        "nin -start b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "nin +guide b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "nin -guide b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "nin +b b=0002 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0200000000000000000000000000",
        "nin -b b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }

  /// Stick transfer (per axis, with no dead zone by default and the rescaled 0.02 boundary),
  /// trigger scaling and clamping at both ends, digital triggers and the hat.
  @Test
  func axesTriggersAndHat() async {
    var lines: [String] = []
    let steps: [(String, DeviceIdentifier, [InputChange])] = [
      ("ls.1", Self.standard, [.leftStick(x: 0.1, y: -0.1)]),
      ("ls.2", Self.standard, [.leftStick(x: 0.2, y: -1)]),
      ("ls.1,-1", Self.standard, [.leftStick(x: 0.1, y: -1)]),
      ("ls.15", Self.standard, [.leftStick(x: 0.15, y: -0.15)]),
      ("ls.151", Self.standard, [.leftStick(x: 0.151, y: -0.151)]),
      ("rs1.5", Self.standard, [.rightStick(x: 1.5, y: -1.5)]),
      ("lt.5", Self.standard, [.leftTrigger(0.5)]), ("rt2", Self.standard, [.rightTrigger(2)]),
      ("lt-.5", Self.standard, [.leftTrigger(-0.5)]),
      ("l2", Self.standard, [.leftTrigger(0), .press(.leftTriggerButton)]),
      ("r2", Self.standard, [.press(.rightTriggerButton)]),
      ("ne", Self.standard, [.hat(.northEast)]), ("sw", Self.standard, [.hat(.southWest)]),
      ("hat0", Self.standard, [.hat(.neutral)]),
      ("zero", Self.standard, [.leftStick(x: 0, y: 0), .rightStick(x: 0, y: 0)]),
      ("r.01", Self.rescaled, [.leftStick(x: 0.01, y: 0.1)]),
      ("r.02", Self.rescaled, [.leftStick(x: 0.02, y: -0.02)]),
      ("r.03,-1", Self.rescaled, [.leftStick(x: 0.03, y: -1)]),
      ("r1", Self.rescaled, [.leftStick(x: 1, y: -1)]),
    ]
    let output = VirtualOutput()
    for (label, identifier, events) in steps {
      await output.dispatch(events, from: identifier)
      lines += output.render(label)
    }
    #expect(
      lines == [
        "ls.1 b=0000 h=0 ls=3276,-3276 rs=0,0 t=0,0 f=00 +1", "  out 0000cc0c34f30000000000000000",
        "ls.2 b=0000 h=0 ls=6553,-32767 rs=0,0 t=0,0 f=00 +1", "  out 0000991901800000000000000000",
        "ls.1,-1 b=0000 h=0 ls=3276,-32767 rs=0,0 t=0,0 f=00 +1",
        "  out 0000cc0c01800000000000000000",
        "ls.15 b=0000 h=0 ls=4915,-4915 rs=0,0 t=0,0 f=00 +1", "  out 00003313cdec0000000000000000",
        "ls.151 b=0000 h=0 ls=4947,-4947 rs=0,0 t=0,0 f=00 +1",
        "  out 00005313adec0000000000000000",
        "rs1.5 b=0000 h=0 ls=4947,-4947 rs=32767,-32767 t=0,0 f=00 +1",
        "  out 00005313adecff7f018000000000",
        "lt.5 b=0000 h=0 ls=4947,-4947 rs=32767,-32767 t=16383,0 f=00 +1",
        "  out 00005313adecff7f0180ff3f0000",
        "rt2 b=0000 h=0 ls=4947,-4947 rs=32767,-32767 t=16383,32767 f=00 +1",
        "  out 00005313adecff7f0180ff3fff7f",
        "lt-.5 b=0000 h=0 ls=4947,-4947 rs=32767,-32767 t=0,32767 f=00 +1",
        "  out 00005313adecff7f01800000ff7f",
        "l2 b=0000 h=0 ls=4947,-4947 rs=32767,-32767 t=0,32767 f=10 +1",
        "  out 00005313adecff7f0180ff7fff7f",
        "r2 b=0000 h=0 ls=4947,-4947 rs=32767,-32767 t=0,32767 f=11 +0",
        "ne b=4800 h=2 ls=4947,-4947 rs=32767,-32767 t=0,32767 f=11 +1",
        "  out 00245313adecff7f0180ff7fff7f",
        "sw b=3000 h=6 ls=4947,-4947 rs=32767,-32767 t=0,32767 f=11 +1",
        "  out 00185313adecff7f0180ff7fff7f",
        "hat0 b=0000 h=0 ls=4947,-4947 rs=32767,-32767 t=0,32767 f=11 +1",
        "  out 00005313adecff7f0180ff7fff7f", "zero b=0000 h=0 ls=0,0 rs=0,0 t=0,32767 f=11 +1",
        "  out 00000000000000000000ff7fff7f", "r.01 b=0000 h=0 ls=0,2674 rs=0,0 t=0,0 f=00 +1",
        "  out 00000000720a0000000000000000", "r.02 b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000",
        "r.03,-1 b=0000 h=0 ls=334,-32767 rs=0,0 t=0,0 f=00 +1",
        "  out 00004e0101800000000000000000", "r1 b=0000 h=0 ls=32767,-32767 rs=0,0 t=0,0 f=00 +1",
        "  out 0000ff7f01800000000000000000",
      ]
    )
  }

  /// Guide always publishes on bit 10, independent of label family.
  @Test
  func guideReports() async {
    var lines: [String] = []
    let output = VirtualOutput()
    for (button, labels) in [("guide", ControllerButtonLabels.standard), ("ps", .playStation)] {
      await output.dispatch([.press(.guide)], from: Self.standard, labels: labels)
      lines += output.render("+\(button)")
      await output.dispatch([.release(.guide)], from: Self.standard, labels: labels)
      lines += output.render("-\(button)")
    }
    #expect(
      lines == [
        "+guide b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "-guide b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+ps b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "-ps b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }

  /// Two controls changing within one batch publish one report with the batch applied in order;
  /// aliases share one bit, so releasing either alias clears it while the other is still held.
  @Test
  func twoControlsInOneBatch() async {
    var lines: [String] = []
    let steps: [(String, [InputChange])] = [
      ("+b", [.press(.faceEast)]), ("+a-b", [.press(.faceSouth), .release(.faceEast)]),
      ("+x+y", [.press(.faceWest), .press(.faceNorth)]),
      ("-a-x-y", [.release(.faceSouth), .release(.faceWest), .release(.faceNorth)]),
      ("+a-a", [.press(.faceSouth), .release(.faceSouth)]),
      ("-a+a", [.release(.faceSouth), .press(.faceSouth)]), ("-a", [.release(.faceSouth)]),
      ("+rs", [.press(.rightStickClick)]),
      ("+rpc-rpc", [.press(.rightTrackpadClick), .release(.rightTrackpadClick)]),
      ("-rs", [.release(.rightStickClick)]), ("+start", [.press(.menu)]), ("+opt", [.press(.menu)]),
      ("-opt", [.release(.menu)]), ("-start", [.release(.menu)]),
      // D-pad buttons fold into the one hat, as the pipeline folded them: a later hat replaces
      // a held button, and a button held with a hat direction adds its own.
      ("+dup,east", [.hat(.east)]), ("hat0", [.hat(.neutral)]), ("east,+dup", [.hat(.northEast)]),
      ("-dup", [.hat(.east)]), ("hat0", [.hat(.neutral)]),
    ]
    let output = VirtualOutput()
    for (label, events) in steps {
      await output.dispatch(events, from: Self.standard)
      lines += output.render(label)
    }
    #expect(
      lines == [
        "+b b=0002 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0200000000000000000000000000",
        "+a-b b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0100000000000000000000000000",
        "+x+y b=000d h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0d00000000000000000000000000",
        "-a-x-y b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+a-a b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-a+a b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0100000000000000000000000000",
        "-a b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+rs b=0080 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0002000000000000000000000000",
        "+rpc-rpc b=0080 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-rs b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+start b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 8000000000000000000000000000",
        "+opt b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-opt b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "-start b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+dup,east b=4000 h=3 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0020000000000000000000000000",
        "hat0 b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "east,+dup b=4800 h=2 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0024000000000000000000000000",
        "-dup b=4000 h=3 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0020000000000000000000000000",
        "hat0 b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }
}
