import Testing

@testable import OpenJoystickDriverKit

// Pinned remapped-path transcripts; the rendering rules are on `OutputCharacterizationTests`.
extension OutputCharacterizationTests {
  /// Remapped states reach the device with no stick deadzone on every controller, including the
  /// `11C1:5600` rescaled transfer: a passthrough 0.2 and a default-tuned 0.2 binding both stay
  /// non-zero.
  @Test
  func remappedSmallSticksSkipTheVirtualOutputTransfer() async throws {
    var lines: [String] = []
    for (name, device) in [("std", Self.standard), ("11c1", Self.rescaled)] {
      let passthrough = EngineSession(Self.profile(.passthrough), device: device)
      lines += try await passthrough.step("\(name) ls.2", [.leftStick(x: 0.2, y: -0.1)])
      lines += try await passthrough.step("\(name) ls0", [.leftStick(x: 0, y: 0)])
      let tuned = EngineSession(
        Self.profile(
          .mapped,
          bindings: [
            RemappingBinding(
              source: .axis(.leftStickX),
              destination: .gamepadAxis(.leftStickX),
              axisTuning: .default
            )
          ]
        ),
        device: device
      )
      lines += try await tuned.step("\(name) tuned.2", [.leftStick(x: 0.2, y: 0)])
    }
    #expect(
      lines == [
        "std ls.2", "  pad [] d=[] a=[left_stick_x=6553,left_stick_y=-3276]",
        "    b=0000 h=0 ls=6553,-3276 rs=0,0 t=0,0 f=00 +1", "  out 0000991934f30000000000000000",
        "std ls0", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "std tuned.2", "  pad [] d=[] a=[left_stick_x=3640]",
        "    b=0000 h=0 ls=3640,0 rs=0,0 t=0,0 f=00 +1", "  out 0000380e00000000000000000000",
        "11c1 ls.2", "  pad [] d=[] a=[left_stick_x=6553,left_stick_y=-3276]",
        "    b=0000 h=0 ls=6553,-3276 rs=0,0 t=0,0 f=00 +1", "  out 0000991934f30000000000000000",
        "11c1 ls0", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "11c1 tuned.2", "  pad [] d=[] a=[left_stick_x=3640]",
        "    b=0000 h=0 ls=3640,0 rs=0,0 t=0,0 f=00 +1", "  out 0000380e00000000000000000000",
      ]
    )
  }

  /// Passthrough analog triggers (clamped to `0...1`; from half a pull they also set the digital
  /// flag), trigger clicks (the digital flag and the effective full-scale byte), the d-pad (hat
  /// and bits) and both sticks. Unlike the virtual output path, a neutral hat leaves a d-pad
  /// direction held by a d-pad button source.
  @Test
  func remappedTriggersDpadAndSticks() async throws {
    let session = EngineSession(Self.profile(.passthrough))
    let steps: [(String, [InputChange])] = [
      ("lt.5", [.leftTrigger(0.5)]), ("rt1.5", [.rightTrigger(1.5)]),
      ("lt-.5", [.leftTrigger(-0.5)]), ("+l2", [.press(.leftTriggerButton)]),
      ("-l2", [.release(.leftTriggerButton)]), ("+r2", [.press(.rightTriggerButton)]),
      ("rt0,-r2", [.rightTrigger(0), .release(.rightTriggerButton)]), ("ne", [.hat(.northEast)]),
      ("sw", [.hat(.southWest)]), ("hat0", [.hat(.neutral)]),
      // D-pad buttons fold into the one hat, as the pipeline folded them.
      ("+dup,east", [.hat(.east)]), ("hat0", [.hat(.neutral)]), ("east,+dup", [.hat(.northEast)]),
      ("-dup", [.hat(.east)]), ("hat0", [.hat(.neutral)]), ("ls", [.leftStick(x: 0.5, y: -0.25)]),
      ("ls0", [.leftStick(x: 0, y: 0)]), ("rs", [.rightStick(x: -1, y: 1.5)]),
      ("rs0", [.rightStick(x: 0, y: 0)]),
    ]
    var lines: [String] = []
    for (label, events) in steps { lines += try await session.step(label, events) }
    #expect(
      lines == [
        "lt.5", "  pad [] d=[] a=[left_trigger=16383]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=16383,0 f=10 +1", "  out 00000000000000000000ff3f0000",
        "rt1.5", "  pad [] d=[] a=[left_trigger=16383,right_trigger=32767]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=16383,32767 f=11 +1", "  out 00000000000000000000ff3fff7f",
        "lt-.5", "  pad [] d=[] a=[right_trigger=32767]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,32767 f=01 +1", "  out 000000000000000000000000ff7f",
        "+l2", "  pad [left_trigger_click] d=[] a=[right_trigger=32767]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,32767 f=11 +1", "  out 00000000000000000000ff7fff7f",
        "-l2", "  pad [] d=[] a=[right_trigger=32767]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,32767 f=01 +1", "  out 000000000000000000000000ff7f",
        "+r2", "  pad [right_trigger_click] d=[] a=[right_trigger=32767]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,32767 f=01 +0", "rt0,-r2",
        "  pad [] d=[] a=[right_trigger=32767]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,32767 f=01 +0",
        "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "ne", "  pad [] d=[right,up] a=[]",
        "    b=4800 h=2 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0024000000000000000000000000", "sw",
        "  pad [] d=[down,left] a=[]", "    b=3000 h=6 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0018000000000000000000000000", "hat0", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+dup,east", "  pad [] d=[right] a=[]", "    b=4000 h=3 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0020000000000000000000000000", "hat0", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "east,+dup", "  pad [] d=[right,up] a=[]", "    b=4800 h=2 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0024000000000000000000000000", "-dup", "  pad [] d=[right] a=[]",
        "    b=4000 h=3 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0020000000000000000000000000", "hat0",
        "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "ls",
        "  pad [] d=[] a=[left_stick_x=16383,left_stick_y=-8191]",
        "    b=0000 h=0 ls=16383,-8191 rs=0,0 t=0,0 f=00 +1", "  out 0000ff3f01e00000000000000000",
        "ls0", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "rs",
        "  pad [] d=[] a=[right_stick_x=-32767,right_stick_y=32767]",
        "    b=0000 h=0 ls=0,0 rs=-32767,32767 t=0,0 f=00 +1", "  out 0000000000000180ff7f00000000",
        "rs0", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000",
      ]
    )
  }

  /// An axis remapped onto a trigger axis also sets that trigger's digital flag, which reports
  /// read as a full press while the analog value is zero, at the normalization threshold.
  @Test
  func remappedTriggerAxisSetsTheDigitalTriggerFlag() async throws {
    let session = EngineSession(
      Self.profile(
        .mapped,
        bindings: [
          RemappingBinding(
            source: .axis(.rightTrigger),
            destination: .gamepadAxis(.leftTrigger),
            axisTuning: .default
          )
        ]
      )
    )
    var lines = try await session.step("rt1", [.rightTrigger(1)])
    lines += try await session.step("rt0", [.rightTrigger(0)])
    #expect(
      lines == [
        "rt1", "  pad [] d=[] a=[left_trigger=32767]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=32767,0 f=10 +1", "  out 00000000000000000000ff7f0000",
        "rt0", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000",
      ]
    )
  }
}
