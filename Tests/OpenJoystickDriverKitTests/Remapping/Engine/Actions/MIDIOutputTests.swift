import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Records what the engine asks of the MIDI output, without a CoreMIDI source.
final class RecordingMIDIOutput: RemappingMIDIOutput, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []
  private let refusal: (any Error)?

  init(refusal: (any Error)? = nil) { self.refusal = refusal }

  func open() throws {
    if let refusal { throw refusal }
    append("open")
  }

  func send(_ message: RemappingMIDIMessage) {
    append(message.bytes.map { unsafe String(format: "%02X", $0) }.joined(separator: " "))
  }

  func close() { append("close") }

  var events: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  private func append(_ event: String) {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(event)
  }
}

struct MIDIOutputTests {
  private let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  // MARK: Coding and validation

  @Test
  func destinationsRoundTripAsTheirDocumentShape() throws {
    let cases: [(RemappingDestination, String)] = [
      (
        .midiNote(channel: 1, note: 60, velocity: 100),
        #"{"channel":1,"note":60,"type":"MidiNote","velocity":100}"#
      ),
      (
        .midiControlChange(channel: 16, controller: 127),
        #"{"channel":16,"controller":127,"type":"MidiControlChange"}"#
      ),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for (destination, json) in cases {
      let data = try encoder.encode(destination)
      #expect(String(bytes: data, encoding: .utf8) == json)
      #expect(try JSONDecoder().decode(RemappingDestination.self, from: data) == destination)
    }
  }

  @Test
  func outOfRangeAndMisplacedFieldsAreRejected() {
    let rejected = [
      #"{"type":"MidiNote","channel":0,"note":60,"velocity":100}"#,
      #"{"type":"MidiNote","channel":17,"note":60,"velocity":100}"#,
      #"{"type":"MidiNote","channel":1,"note":128,"velocity":100}"#,
      #"{"type":"MidiNote","channel":1,"note":60,"velocity":0}"#,
      #"{"type":"MidiNote","channel":1,"note":60,"velocity":128}"#,
      #"{"type":"MidiNote","channel":1,"note":60}"#,
      #"{"type":"MidiNote","channel":1,"note":60,"velocity":100,"controller":1}"#,
      #"{"type":"MidiControlChange","channel":0,"controller":1}"#,
      #"{"type":"MidiControlChange","channel":1,"controller":128}"#,
      #"{"type":"MidiControlChange","channel":1,"controller":1,"velocity":100}"#,
    ]
    for json in rejected {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RemappingDestination.self, from: Data(json.utf8))
      }
    }
  }

  @Test
  func builtOutOfRangeDestinationsFailValidation() {
    for destination in [
      RemappingDestination.midiNote(channel: 0, note: 60, velocity: 100),
      .midiNote(channel: 1, note: 128, velocity: 100),
      .midiNote(channel: 1, note: 60, velocity: 0),
      .midiControlChange(channel: 17, controller: 1),
    ] {
      #expect(throws: RemappingValidationError.invalidMIDIDestination) {
        try profile(destination).validate()
      }
    }
  }

  @Test
  func controlChangeFitsAnAxisAndNoteDoesNot() throws {
    let tuning = RemappingAxisTuning(deadzone: 0, gain: 1)
    try profile(
      .midiControlChange(channel: 1, controller: 1),
      source: .axis(.leftTrigger),
      tuning: tuning
    ).validate()
    #expect(throws: RemappingValidationError.incompatibleSourceAndDestination(index: 0)) {
      try profile(
        .midiNote(channel: 1, note: 60, velocity: 100),
        source: .axis(.leftTrigger),
        tuning: tuning
      ).validate()
    }
  }

  // MARK: Messages

  @Test
  func messagesHaveTheirWireBytes() {
    let on = RemappingMIDIMessage.noteOn(channel: 1, note: 60, velocity: 100)
    let off = RemappingMIDIMessage.noteOff(channel: 1, note: 60)
    let change = RemappingMIDIMessage.controlChange(channel: 2, controller: 1, value: 127)
    #expect(on.bytes == [0x90, 0x3C, 0x64])
    #expect(off.bytes == [0x80, 0x3C, 0x00])
    #expect(change.bytes == [0xB1, 0x01, 0x7F])
  }

  // MARK: Engine

  @Test
  func noteOnOnPressAndNoteOffOnRelease() {
    var state = RemappingEngineState()
    let note = profile(.midiNote(channel: 1, note: 60, velocity: 100))
    let down = state.process(inputs: [.press(.south)], from: identifier, profile: note, at: 0)
    let up = state.process(inputs: [.release(.south)], from: identifier, profile: note, at: 1)
    #expect(down == [.midi(.noteOn(channel: 1, note: 60, velocity: 100))])
    #expect(up == [.midi(.noteOff(channel: 1, note: 60))])
  }

  @Test
  func controlChangeOnAButtonSends127ThenZero() {
    var state = RemappingEngineState()
    let cc = profile(.midiControlChange(channel: 3, controller: 7))
    let down = state.process(inputs: [.press(.south)], from: identifier, profile: cc, at: 0)
    let up = state.process(inputs: [.release(.south)], from: identifier, profile: cc, at: 1)
    #expect(down == [.midi(.controlChange(channel: 3, controller: 7, value: 127))])
    #expect(up == [.midi(.controlChange(channel: 3, controller: 7, value: 0))])
  }

  @Test
  func controlChangeOnATriggerScalesAndNeverRepeatsAValue() {
    var state = RemappingEngineState()
    let cc = profile(
      .midiControlChange(channel: 2, controller: 1),
      source: .axis(.leftTrigger),
      tuning: RemappingAxisTuning(deadzone: 0, gain: 1)
    )
    var values: [Int] = []
    for (index, level) in [Float](arrayLiteral: 0, 0.25, 0.251, 0.6, 0.6, 1, 1, 0).enumerated() {
      let actions = state.process(
        inputs: [.leftTrigger(level)],
        from: identifier,
        profile: cc,
        at: UInt64(index)
      )
      for case .midi(.controlChange(channel: 2, controller: 1, let value)) in actions {
        values.append(value)
      }
    }
    #expect(values == [32, 76, 127, 0])
  }

  @Test
  func theSourceOpensBeforeTheNoteAndClosesAfterTheNoteOff() async throws {
    let midi = RecordingMIDIOutput()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), midiOutput: midi)
    let note = profile(.midiNote(channel: 1, note: 60, velocity: 100))
    try await engine.process(inputs: [.press(.south)], from: identifier, using: note, at: 0)
    try await engine.setProfile(nil, for: identifier)
    #expect(midi.events == ["open", "90 3C 64", "80 3C 00", "close"])
  }

  @Test
  func aProfileWithoutMIDIOpensNoSource() async throws {
    let midi = RecordingMIDIOutput()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), midiOutput: midi)
    let keys = profile(.keyboard(key: .a, modifiers: []))
    try await engine.process(inputs: [.press(.south)], from: identifier, using: keys, at: 0)
    #expect(midi.events.isEmpty)
  }

  @Test
  func aRefusedSourceNamesTheErrorAndSendsNothing() async {
    let refusal = RemappingMIDIError.sourceRefused(status: -10844)
    let midi = RecordingMIDIOutput(refusal: refusal)
    let engine = RemappingEventEngine(sink: RemappingTestSink(), midiOutput: midi)
    let note = profile(.midiNote(channel: 1, note: 60, velocity: 100))
    await #expect(throws: refusal) {
      try await engine.process(inputs: [.press(.south)], from: identifier, using: note, at: 0)
    }
    #expect(refusal.errorCode == .midiSourceRefused)
    #expect(midi.events.isEmpty)
  }

  // MARK: Helpers

  private func profile(
    _ destination: RemappingDestination,
    source: RemappingSource = .button(.south),
    tuning: RemappingAxisTuning? = nil
  ) -> RemappingProfile {
    RemappingProfile(
      name: "P",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: .systemInput,
      bindings: [
        RemappingBinding(source: source, destination: destination, axisTuning: tuning)
      ]
    )
  }
}
