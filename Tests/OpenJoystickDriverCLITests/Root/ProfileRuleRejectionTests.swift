import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

private let firstID = "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D01"
private let secondID = "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D02"
private let south = #"{"type": "Button", "button": "South"}"#

/// A profile for one controller model with the given bindings.
private func document(id: String = firstID, productID: Int = 3302, bindings: [String]) -> String {
  """
  {
    "apiVersion": "openjoystickdriver/v1alpha3", "kind": "Profile", "id": "\(id)",
    "name": "Fixture", "applicationScope": {"type": "Global"},
    "device": {"vendorID": 1356, "productID": \(productID)},
    "bindings": [\(bindings.joined(separator: ","))]
  }
  """
}

private func binding(_ number: Int, source: String, destination: String) -> String {
  """
  {"id": "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4E0\(number)", "source": \(source),
    "destination": \(destination)}
  """
}

private func key(_ number: Int, source: String) -> String {
  binding(
    number,
    source: source,
    destination: #"{"type": "Keyboard", "key": "Space", "modifiers": []}"#
  )
}

private func region(
  _ inner: Double,
  _ outer: Double,
  stick: String = "Left",
  sector: String = ""
) -> String {
  """
  {"type": "StickRegion", "stick": "\(stick)", "innerRadius": \(inner), "outerRadius": \(outer),
    "hysteresis": 0.05\(sector)}
  """
}

private func band(_ from: Double, _ to: Double) -> String {
  #"{"type": "TriggerBand", "trigger": "Left", "from": \#(from), "to": \#(to), "hysteresis": 0.05}"#
}

private func area(x: Double, y: Double, width: Double, height: Double) -> String {
  """
  {"type": "TouchArea", "surface": "Primary", "x": \(x), "y": \(y), "width": \(width),
    "height": \(height)}
  """
}

private func load(_ json: String) throws -> RemappingProfile {
  try RemappingProfileFileStore.load(from: PropertyListFixture.data(json: json))
}

private final class VoiceList: RemappingSpeechOutput, @unchecked Sendable {
  let voices: Set<String>
  init(voices: Set<String>) { self.voices = voices }
  func speak(_: String, voice _: String?, for _: LogicalControllerID) {}
  func stopSpeech(for _: LogicalControllerID) {}
  func hasVoice(_ identifier: String) -> Bool { voices.contains(identifier) }
}

// Rules that `ProfileSchemaTests` cannot reach through the shared rich document, each with a
// fixture of its own. Swift rejects every case and the schema accepts every case (`schema:
// false`), because each rule compares fields or sources, or needs state outside the document.
struct ProfileRuleRejectionTests {
  /// Rules of one source: the decoder refuses the document, the schema accepts it.
  @Test(arguments: [
    ("touch region past the right edge", area(x: 0.6, y: 0, width: 0.5, height: 0.5)),
    ("touch region past the bottom edge", area(x: 0, y: 0.9, width: 0.5, height: 0.2)),
    (
      "stick region with equal angles",
      region(0, 1, sector: #", "fromDegrees": 90, "toDegrees": 90"#)
    ),
  ])
  func aRegionRuleIsRefusedByTheDecoderOnly(problem: String, source: String) throws {
    let json = document(bindings: [key(1, source: source)])
    do {
      _ = try load(json)
      Issue.record("\(problem): the profile loads")
    } catch {
      #expect(RemappingProfileFileStore.problemCode(error) == .invalidProfile, "\(problem)")
    }
    #expect(try CLIOutputSchema.profileIssues(inJSON: json).isEmpty, "\(problem)")
  }

  /// Two regions of one stick or two bands of one trigger that share a position.
  @Test(arguments: [
    ("stick regions overlap in radius", region(0.2, 0.7), region(0.5, 1)),
    (
      "stick regions overlap in angle",
      region(0, 1, sector: #", "fromDegrees": 0, "toDegrees": 90"#),
      region(0, 1, sector: #", "fromDegrees": 45, "toDegrees": 135"#)
    ),
    (
      "stick regions overlap across 0 degrees",
      region(0, 1, sector: #", "fromDegrees": 350, "toDegrees": 10"#),
      region(0, 1, sector: #", "fromDegrees": 5, "toDegrees": 20"#)
    ),
    ("trigger bands overlap", band(0.1, 0.5), band(0.4, 0.9)),
  ])
  func overlappingRegionsAreRefusedByTheDecoderOnly(
    problem: String,
    first: String,
    second: String
  ) throws {
    let json = document(bindings: [key(1, source: first), key(2, source: second)])
    do {
      _ = try load(json)
      Issue.record("\(problem): the profile loads")
    } catch {
      #expect(RemappingProfileFileStore.problemCode(error) == .invalidProfile, "\(problem)")
    }
    #expect(try CLIOutputSchema.profileIssues(inJSON: json).isEmpty, "\(problem)")
  }

  @Test
  func regionsThatTouchOrBelongToOtherSticksAreAccepted() throws {
    let json = document(bindings: [
      key(1, source: region(0.2, 0.5)), key(2, source: region(0.5, 1)),
      key(3, source: region(0.2, 1, stick: "Right")),
      key(4, source: band(0.1, 0.5)), key(5, source: band(0.5, 0.9)),
    ])
    _ = try load(json)
    #expect(try CLIOutputSchema.profileIssues(inJSON: json).isEmpty)
  }

  /// The document of a profile switch is valid; the check needs the other profiles.
  @Test
  func aProfileSwitchToAnotherModelIsRefusedByTheLibraryCheckOnly() throws {
    let foreign = try load(
      document(id: secondID, productID: 9999, bindings: [key(1, source: south)])
    )
    let json = document(bindings: [
      binding(
        1,
        source: south,
        destination: #"{"type": "ProfileSwitch", "profile": "\#(secondID)"}"#
      )
    ])
    let switching = try load(json)
    #expect(try CLIOutputSchema.profileIssues(inJSON: json).isEmpty)
    #expect(throws: RemappingValidationError.switchProfileForOtherModel(foreign.id)) {
      try switching.validateProfileSwitches(among: [switching, foreign])
    }
    let sameModel = try load(document(id: secondID, bindings: [key(1, source: south)]))
    try switching.validateProfileSwitches(among: [switching, sameModel])
  }

  /// The document of a `Speak` destination is valid; the check needs the voices of this Mac.
  @Test
  func aSpeakVoiceThatTheMacLacksIsRefusedByTheLibraryCheckOnly() throws {
    let json = document(bindings: [
      binding(
        1,
        source: south,
        destination: #"{"type": "Speak", "text": "Hi", "voice": "no.such.voice"}"#
      )
    ])
    let profile = try load(json)
    #expect(try CLIOutputSchema.profileIssues(inJSON: json).isEmpty)
    #expect(throws: RemappingValidationError.unknownSpeechVoice("no.such.voice")) {
      try profile.validateSpeechVoices(using: VoiceList(voices: []))
    }
    try profile.validateSpeechVoices(using: VoiceList(voices: ["no.such.voice"]))
  }
}
