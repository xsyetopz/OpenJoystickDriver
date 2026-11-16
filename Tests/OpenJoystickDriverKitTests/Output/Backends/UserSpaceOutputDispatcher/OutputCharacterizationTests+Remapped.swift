import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Pinned remapped-path transcripts; the rendering rules are on `OutputCharacterizationTests`.
extension OutputCharacterizationTests {
  /// Mapped output emits only the bound destination; an unbound press emits nothing.
  @Test
  func buttonToButton() async throws {
    let session = EngineSession(
      Self.profile(
        .mapped,
        bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
      )
    )
    var lines = try await session.step("+a", [.press(.south)])
    lines += try await session.step("+b", [.press(.east)])
    lines += try await session.step("-a", [.release(.south)])
    lines += try await session.step("+a", [.press(.south)])
    try await session.engine.releaseAll(for: Self.engineDevice)
    lines += session.recorder.take("release-all")
    #expect(
      lines == [
        "+a", "  pad [North] d=[] a=[]", "    b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0800000000000000000000000000", "+b", "-a", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000", "+a",
        "  pad [North] d=[] a=[]", "    b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0800000000000000000000000000", "release-all", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }

  /// A keyboard destination with modifiers orders modifiers around the key.
  @Test
  func buttonToKey() async throws {
    let session = EngineSession(
      Self.profile(
        .disabled,
        bindings: [
          RemappingBinding(source: .button(.south), destination: Self.key(.c, [.meta, .shift]))
        ]
      )
    )
    var lines = try await session.step("+a", [.press(.south)])
    lines += try await session.step("-a", [.release(.south)])
    #expect(
      lines == [
        "+a", "  sys modifier-down Meta", "  sys modifier-down Shift", "  sys key-down KeyC", "-a",
        "  sys key-up KeyC", "  sys modifier-up Shift", "  sys modifier-up Meta",
      ]
    )
  }

  /// A stick axis bound to another stick axis, through the default axis tuning.
  @Test
  func axisToAxis() async throws {
    let session = EngineSession(
      Self.profile(
        .mapped,
        bindings: [
          RemappingBinding(
            source: .axis(.leftStickX),
            destination: .gamepadAxis(.rightStickX),
            axisTuning: .default
          )
        ]
      )
    )
    var lines = try await session.step("ls.5", [.leftStick(x: 0.5, y: 0.25)])
    lines += try await session.step("ls-1", [.leftStick(x: -1, y: 0.25)])
    lines += try await session.step("ls.05", [.leftStick(x: 0.05, y: 0)])
    lines += try await session.step("ls0", [.leftStick(x: 0, y: 0)])
    #expect(
      lines == [
        "ls.5", "  pad [] d=[] a=[RightStickX=14563]",
        "    b=0000 h=0 ls=0,0 rs=14562,0 t=0,0 f=00 +1", "  out 000000000000e238000000000000",
        "ls-1", "  pad [] d=[] a=[RightStickX=-32767]",
        "    b=0000 h=0 ls=0,0 rs=-32767,0 t=0,0 f=00 +1", "  out 0000000000000180000000000000",
        "ls.05", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "ls0",
      ]
    )
  }

  /// A simultaneous chord (south+east to c) and a sequence (south, north to d) with their timing.
  @Test
  func chordAndSequence() async throws {
    let session = EngineSession(
      Self.profile(
        .disabled,
        chords: [
          RemappingChord(
            sources: [.button(.south), .button(.east)],
            destination: Self.key(.c),
            mode: .simultaneous,
            windowMs: 50
          )
        ],
        sequences: [
          RemappingSequence(
            sources: [.button(.south), .button(.north)],
            windowMs: 200,
            destination: Self.key(.d)
          )
        ]
      )
    )
    let ms: UInt64 = 1_000_000
    var lines = try await session.step("+a@0", [.press(.south)], at: 0)
    lines += try await session.step("+b@10", [.press(.east)], at: 10 * ms)
    lines += try await session.step(
      "-a-b@20",
      [.release(.south), .release(.east)],
      at: 20 * ms
    )
    lines += try await session.step("+a@1000", [.press(.south)], at: 1_000 * ms)
    lines += try await session.tick("tick@1100", at: 1_100 * ms)
    lines += try await session.step("-a@1110", [.release(.south)], at: 1_110 * ms)
    lines += try await session.step("+y@1120", [.press(.north)], at: 1_120 * ms)
    lines += try await session.tick("tick@1500", at: 1_500 * ms)
    lines += try await session.step("-y@1510", [.release(.north)], at: 1_510 * ms)
    lines += try await session.tick("tick@2000", at: 2_000 * ms)
    #expect(
      lines == [
        "+a@0", "+b@10", "  sys key-down KeyC", "-a-b@20", "  sys key-up KeyC", "+a@1000",
        "tick@1100",
        "-a@1110", "+y@1120", "  sys key-down KeyD", "  sys key-up KeyD", "tick@1500", "-y@1510",
        "tick@2000",
      ]
    )
  }

  /// Passthrough carries each family's controls as engine sources.
  ///
  /// A real DualSense report drives the PlayStation family: Create reaches Share (bit 15, not View
  /// bit 9), Options reaches Start, PS reaches Guide. Standard View, Menu, Guide and the right pad
  /// click follow as parser events.
  @Test
  func passthroughFamilyControls() async throws {
    let playStation = EngineSession(Self.profile(.passthrough), device: Self.playStation)
    let driver = DualSenseDriver()
    var previous = ControllerState.neutral
    var lines: [String] = []
    for (label, offset, mask): (String, Int, UInt8) in [
      ("create", 9, 0x10), ("options", 9, 0x20), ("ps", 10, 0x01), ("neutral", 0, 0),
    ] {
      var report = [UInt8](repeating: 0, count: 64)
      report[0] = 0x01
      for index in 1...4 { report[index] = 128 }
      report[8] = 0x08
      if mask != 0 { report[offset] |= mask }
      let event = try #require(try driver.parseReport(Data(report)))
      let parsed = Self.renderChanges(from: previous, to: event)
      previous = event.state
      lines += try await playStation.step("ds \(label) [\(parsed)]", event: event)
    }
    let standard = EngineSession(Self.profile(.passthrough), device: Self.standard)
    for (button, control) in [
      ("back", Control.back), ("start", .start), ("guide", .guide),
      ("rightPadClick", .rightTrackpadClick),
    ] {
      lines += try await standard.step("+\(button)", [.press(control)])
      lines += try await standard.step("-\(button)", [.release(control)])
    }
    #expect(
      lines == [
        "ds create [+Back motion touch]", "  pad [Back] d=[] a=[]",
        "    b=0200 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 4000000000000000000000000000",
        "ds options [-Back +Start motion touch]", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "  pad [Start] d=[] a=[]", "    b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 8000000000000000000000000000", "ds ps [-Start +Guide motion touch]",
        "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "  pad [Guide] d=[] a=[]",
        "    b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "ds neutral [-Guide motion touch]", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000", "+back",
        "  pad [Back] d=[] a=[]", "    b=0200 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 4000000000000000000000000000", "-back", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+start", "  pad [Start] d=[] a=[]", "    b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 8000000000000000000000000000", "-start", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+guide", "  pad [Guide] d=[] a=[]", "    b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0040000000000000000000000000", "-guide", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+rightPadClick", "-rightPadClick",
      ]
    )
  }

  /// The engine emits one state per event of a batch, so a batch's intermediate states reach the
  /// virtual device; aliases stay held while either source is active.
  @Test
  func twoControlsInOneRemappedBatch() async throws {
    let session = EngineSession(Self.profile(.passthrough))
    let steps: [(String, [InputChange])] = [
      ("+b", [.press(.east)]), ("+a-b", [.press(.south), .release(.east)]),
      ("+x+y", [.press(.west), .press(.north)]),
      ("-a-x-y", [.release(.south), .release(.west), .release(.north)]),
      ("+a-a", [.press(.south), .release(.south)]), ("+rs", [.press(.rightStickClick)]),
      ("+rpc-rpc", [.press(.rightTrackpadClick), .release(.rightTrackpadClick)]),
      ("-rs", [.release(.rightStickClick)]),
    ]
    var lines: [String] = []
    for (label, events) in steps { lines += try await session.step(label, events) }
    #expect(
      lines == [
        "+b", "  pad [East] d=[] a=[]", "    b=0002 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0200000000000000000000000000", "+a-b", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "  pad [South] d=[] a=[]", "    b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0100000000000000000000000000", "+x+y", "  pad [South,West] d=[] a=[]",
        "    b=0005 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0500000000000000000000000000",
        "  pad [North,South,West] d=[] a=[]", "    b=000d h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0d00000000000000000000000000", "-a-x-y", "  pad [North,West] d=[] a=[]",
        "    b=000c h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0c00000000000000000000000000",
        "  pad [North] d=[] a=[]", "    b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0800000000000000000000000000", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000", "+a-a",
        "+rs", "  pad [RightStickClick] d=[] a=[]", "    b=0080 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0002000000000000000000000000", "+rpc-rpc", "-rs", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }

  /// Keyboard destinations of one batch follow the releases-before-presses order.
  @Test
  func twoKeysInOneBatch() async throws {
    let session = EngineSession(
      Self.profile(
        .disabled,
        bindings: [
          RemappingBinding(source: .button(.south), destination: Self.key(.x)),
          RemappingBinding(source: .button(.east), destination: Self.key(.y)),
        ]
      )
    )
    var lines = try await session.step("+b", [.press(.east)])
    lines += try await session.step("+a-b", [.press(.south), .release(.east)])
    lines += try await session.step("-a+b", [.release(.south), .press(.east)])
    lines += try await session.step("+a", [.press(.south)])
    #expect(
      lines == [
        "+b", "  sys key-down KeyY", "+a-b", "  sys key-up KeyY", "  sys key-down KeyX", "-a+b",
        "  sys key-up KeyX", "  sys key-down KeyY", "+a", "  sys key-down KeyX",
      ]
    )
  }
}
