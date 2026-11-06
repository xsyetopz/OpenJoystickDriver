import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualDeviceTests {
  private static let header = #""apiVersion":"openjoystickdriver/v1alpha2","kind":"VirtualDevice""#

  @Test
  func theBundledRecordsDefineBothPersonasWithTheirIdentities() throws {
    let generic = try #require(VirtualDevice.definition(of: .generic).profile)
    #expect((generic.vendorID, generic.productID) == (0x1209, 0x4A4F))
    let sdl = try #require(VirtualDevice.definition(of: .sdlCompatible).profile)
    #expect((sdl.vendorID, sdl.productID) == (0x045E, 0x0B0C))
  }

  @Test
  func theRecordsStateWhichPersonaWorksWithDefaultSDLHints() throws {
    #expect(VirtualDevice.definition(of: .generic).worksWithDefaultSDLHints == true)
    #expect(VirtualDevice.definition(of: .sdlCompatible).worksWithDefaultSDLHints == true)
  }

  @Test
  func aDefinitionWithoutOrWithAMalformedHintsFieldIsRefused() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Resources/VirtualDevices/virtual-device.generic.json")
    var document = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    _ = try VirtualDevice.decode(
      JSONSerialization.data(withJSONObject: document),
      source: .unnamed,
      requiresMatch: false
    )
    for value: Any? in [nil, "yes", 1] {
      document["worksWithDefaultSDLHints"] = value
      #expect(throws: ControllerRecordProblem.self, "\(String(describing: value))") {
        try VirtualDevice.decode(
          JSONSerialization.data(withJSONObject: document),
          source: .unnamed,
          requiresMatch: false
        )
      }
    }
  }

  @Test
  func aSelectionRecordHoldsNoHintsField() {
    let document =
      "{\(Self.header),\"persona\":\"Generic\","
      + "\"match\":{\"vendorID\":1,\"productID\":2},\"worksWithDefaultSDLHints\":true}"
    #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(Data(document.utf8), source: .unnamed, requiresMatch: false)
    }
  }

  @Test(arguments: [
    #"{"apiVersion":"openjoystickdriver/v2","kind":"VirtualDevice","persona":"Generic"}"#,
    #"{"kind":"VirtualDevice","persona":"Generic"}"#,
    #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"Persona","persona":"Generic"}"#,
    #"{"apiVersion":"openjoystickdriver/v1alpha2","persona":"Generic"}"#,
  ])
  func aBadHeaderIsRefusedWithE5001(document: String) {
    let problem = #expect(throws: DocumentHeaderProblem.self) {
      try VirtualDevice.decode(Data(document.utf8), source: .unnamed, requiresMatch: false)
    }
    #expect(problem?.code == .unsupportedAPIVersion)
    #expect(problem?.description.hasPrefix("E5001") == true)
  }

  @Test
  func aDocumentWithAnUnknownPersonaIsRefused() {
    let document = "{\(Self.header),\"persona\":\"NotAPersona\"}"
    #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(Data(document.utf8), source: .unnamed, requiresMatch: false)
    }
  }

  @Test
  func aProblemWithAVirtualDeviceIsAnInvalidControllerRecord() {
    let document = "{\(Self.header),\"persona\":\"NotAPersona\"}"
    let problem = #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(Data(document.utf8), source: .unnamed, requiresMatch: false)
    }
    #expect(problem?.code == .invalidControllerRecord)
    #expect(problem.flatMap { ControllerRecordSet.problemCode($0) } == .invalidControllerRecord)
  }
}
