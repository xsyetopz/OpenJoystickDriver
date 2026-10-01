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

  @Test(arguments: [
    (
      #""id":"1364CBAC-B60B-4E11-B3E7-C38AD809FE42","#, "",
      "pad.json is not a valid profile: the field 'id' is missing"
    ),
    (
      #""name":"Pad""#, #""bogus":1,"name":"Pad""#,
      "pad.json is not a valid profile: unknown field(s): bogus"
    ),
    (
      #""vendorID":1356"#, #""vendorID":"x""#,
      "pad.json is not a valid profile: the field 'device.vendorID' has the wrong type"
    ),
    (
      #""applicationScope""#, #"applicationScope""#,
      "pad.json is not a valid profile: it is not valid JSON"
    ),
  ])
  func aProblemNamesTheField(replacing: String, with: String, message: String) {
    #expect(problem(Self.profile.replacingOccurrences(of: replacing, with: with)) == message)
  }
}
