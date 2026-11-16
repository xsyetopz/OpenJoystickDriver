import Foundation
import Testing

@testable import OpenJoystickDriverKit

final class RecordingSpeechOutput: RemappingSpeechOutput, @unchecked Sendable {
  enum Event: Equatable {
    case speak(String, String?, LogicalControllerID)
    case stop(LogicalControllerID)
  }

  private let lock = NSLock()
  private var recorded: [Event] = []
  let voices: Set<String>

  init(voices: Set<String> = []) { self.voices = voices }

  func events() -> [Event] { lock.withLock { recorded } }

  func speak(_ text: String, voice: String?, for identifier: LogicalControllerID) {
    lock.withLock { recorded.append(.speak(text, voice, identifier)) }
  }

  func stopSpeech(for identifier: LogicalControllerID) {
    lock.withLock { recorded.append(.stop(identifier)) }
  }

  func hasVoice(_ identifier: String) -> Bool { voices.contains(identifier) }
}

struct SpeechOutputTests {
  private let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
  private let speech = RecordingSpeechOutput(voices: ["com.apple.voice.test"])

  @Test
  func speakRoundTripsAsItsDocumentShape() throws {
    let cases: [(RemappingDestination, String)] = [
      (.speak(text: "Reloading", voice: nil), #"{"text":"Reloading","type":"Speak"}"#),
      (
        .speak(text: "Hi", voice: "com.apple.voice.test"),
        #"{"text":"Hi","type":"Speak","voice":"com.apple.voice.test"}"#
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
  func emptyAndLongTextAndEmptyVoiceAreRejectedWithFieldPath() throws {
    try profile(.speak(text: String(repeating: "a", count: 128), voice: nil)).validate()
    let rejected: [(RemappingDestination, String)] = [
      (.speak(text: "", voice: nil), "text"),
      (.speak(text: String(repeating: "a", count: 129), voice: nil), "text"),
      (.speak(text: "Hi", voice: ""), "voice"),
    ]
    for (destination, field) in rejected {
      #expect(throws: RemappingValidationError.invalidSpeech(field: field)) {
        try profile(destination).validate()
      }
    }
  }

  @Test
  func unknownVoiceNamesVoice() throws {
    try profile(.speak(text: "Hi", voice: "com.apple.voice.test")).validateSpeechVoices(
      using: speech
    )
    try profile(.speak(text: "Hi", voice: nil)).validateSpeechVoices(using: speech)
    #expect(throws: RemappingValidationError.unknownSpeechVoice("nope")) {
      try profile(.speak(text: "Hi", voice: "nope")).validateSpeechVoices(using: speech)
    }
  }

  @Test
  func macroStepsCannotSpeak() {
    let macro = RemappingMacro(name: "M", steps: [.press(.speak(text: "Hi", voice: nil))])
    #expect(throws: RemappingValidationError.invalidMacroStepDestination(index: 0, step: 0)) {
      try profile(.speak(text: "Hi", voice: nil), macros: [macro]).validate()
    }
  }

  @Test
  func onePressSpeaksOnceAndReleaseSaysNothing() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink(), speechOutput: speech)
    let profile = profile(.speak(text: "Reloading", voice: nil))
    try await engine.process(
      inputs: [.press(.south), .release(.south)],
      from: identifier,
      using: profile,
      at: 1
    )
    #expect(speech.events() == [.speak("Reloading", nil, identifier)])
  }

  @Test
  func restartOnPressSpeaksAgainFromStart() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink(), speechOutput: speech)
    let profile = profile(.speak(text: "Reloading", voice: nil))
    for time in [UInt64(1), 2] {
      try await engine.process(
        inputs: [.press(.south), .release(.south)],
        from: identifier,
        using: profile,
        at: time
      )
    }
    #expect(speech.events() == Array(repeating: .speak("Reloading", nil, identifier), count: 2))
  }

  @Test
  func pauseStopsSpeech() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink(), speechOutput: speech)
    let profile = profile(
      .speak(text: "Hi", voice: nil),
      extra: [RemappingBinding(source: .button(.east), destination: .pause(.on))]
    )
    try await engine.process(inputs: [.press(.south)], from: identifier, using: profile, at: 1)
    try await engine.process(inputs: [.press(.east)], from: identifier, using: profile, at: 2)
    #expect(speech.events() == [.speak("Hi", nil, identifier), .stop(identifier)])
  }

  @Test
  func deactivationStopsSpeechOnlyWhileSpeaking() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink(), speechOutput: speech)
    let profile = profile(.speak(text: "Hi", voice: nil))
    try await engine.process(inputs: [], from: identifier, using: profile, at: 1)
    try await engine.drain()
    #expect(speech.events().isEmpty)
    try await engine.process(inputs: [.press(.south)], from: identifier, using: profile, at: 2)
    try await engine.drain()
    #expect(speech.events() == [.speak("Hi", nil, identifier), .stop(identifier)])
  }

  private func profile(
    _ destination: RemappingDestination,
    extra: [RemappingBinding] = [],
    macros: [RemappingMacro] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "P",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(source: .button(.south), destination: destination)] + extra,
      macros: macros
    )
  }
}
