import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct DocumentProblemTests {
  private static let profile = """
    {"applicationScope":{"type":"global"},"bindings":[],"chords":[],\
    "device":{"productID":616,"vendorID":1356},"id":"1364CBAC-B60B-4E11-B3E7-C38AD809FE42",\
    "layers":[],"name":"Pad","outputPolicy":{"physicalInput":"shared",\
    "virtualGamepad":"passthrough"},"sequences":[]}
    """

  private func problem(_ text: String) -> String? {
    do {
      _ = try decodeProfile(Data(text.utf8), source: "pad.json")
      return nil
    } catch { return (error as? CLIFailure)?.message }
  }

  @Test
  func theUnchangedDocumentDecodes() {
    #expect(problem(Self.profile) == nil)
  }

  /// The fields that a problem names; `nil` where the field name is too short to match reliably.
  private static let problems: [(replacing: String, with: String, field: String?)] = [
    (#""id":"1364CBAC-B60B-4E11-B3E7-C38AD809FE42","#, "", nil),
    (#""name":"Pad""#, #""bogus":1,"name":"Pad""#, "bogus"),
    (#""vendorID":1356"#, #""vendorID":"x""#, "device.vendorID"),
    (#""applicationScope""#, #"applicationScope""#, nil),
  ]

  @Test
  func aProblemNamesTheFileAndTheField() {
    for item in Self.problems {
      let message = problem(Self.profile.replacingOccurrences(of: item.replacing, with: item.with))
      #expect(message?.contains("pad.json") == true, "\(item.replacing)")
      if let field = item.field { #expect(message?.contains(field) == true, "\(field)") }
    }
  }

  @Test
  func eachKindOfProblemHasItsOwnMessage() {
    let messages = Self.problems.map {
      problem(Self.profile.replacingOccurrences(of: $0.replacing, with: $0.with))
    }
    #expect(Set(messages.compactMap { $0 }).count == Self.problems.count)
  }
}
