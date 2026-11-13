import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct VirtualDeviceTests {
  private static let header =
    #""apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"VirtualDevice""#

  @Test
  func bundledRecordsDefineBothPersonasWithTheirIdentities() throws {
    let generic = try #require(VirtualDevice.definition(of: .generic).profile)
    #expect((generic.vendorID, generic.productID) == (0x1209, 0x4A4F))
    let sdl = try #require(VirtualDevice.definition(of: .sdlCompatible).profile)
    #expect((sdl.vendorID, sdl.productID) == (0x045E, 0x0B0C))
  }

  @Test
  func recordsStatePersonaWorksWithDefaultSDLHints() {
    #expect(VirtualDevice.definition(of: .generic).worksWithDefaultSDLHints == true)
    #expect(VirtualDevice.definition(of: .sdlCompatible).worksWithDefaultSDLHints == true)
  }

  @Test
  func definitionWithoutOrWithMalformedHintsFieldIsRefused() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Resources/VirtualDevices/virtual-device.generic.plist")
    var document = try PropertyListFixture.dictionary(at: url)
    _ = try VirtualDevice.decode(
      PropertyListFixture.data(tree: document),
      source: .unnamed,
      requiresMatch: false
    )
    for value: Any? in [nil, "yes", 1] {
      document["worksWithDefaultSDLHints"] = value
      #expect(throws: ControllerRecordProblem.self, "\(String(describing: value))") {
        try VirtualDevice.decode(
          PropertyListFixture.data(tree: document),
          source: .unnamed,
          requiresMatch: false
        )
      }
    }
  }

  @Test
  func selectionRecordHoldsNoHintsField() {
    let document =
      "{\(Self.header),\"persona\":\"Generic\","
      + "\"match\":{\"vendorID\":1,\"productID\":2},\"worksWithDefaultSDLHints\":true}"
    #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: document),
        source: .unnamed,
        requiresMatch: false
      )
    }
  }

  @Test(arguments: [
    #"{"apiVersion":"openjoystickdriver/v2","kind":"VirtualDevice","persona":"Generic"}"#,
    #"{"kind":"VirtualDevice","persona":"Generic"}"#,
    #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"Persona","persona":"Generic"}"#,
    #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","persona":"Generic"}"#,
  ])
  func badHeaderIsRefusedWithE5001(document: String) {
    let problem = #expect(throws: DocumentHeaderProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: document),
        source: .unnamed,
        requiresMatch: false
      )
    }
    #expect(problem?.code == .unsupportedAPIVersion)
    #expect(problem?.description.hasPrefix("E5001") == true)
  }

  @Test
  func documentWithUnknownPersonaIsRefused() {
    let document = "{\(Self.header),\"persona\":\"NotAPersona\"}"
    #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: document),
        source: .unnamed,
        requiresMatch: false
      )
    }
  }

  @Test
  func problemWithVirtualDeviceIsInvalidControllerRecord() {
    let document = "{\(Self.header),\"persona\":\"NotAPersona\"}"
    let problem = #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: document),
        source: .unnamed,
        requiresMatch: false
      )
    }
    #expect(problem?.code == .invalidControllerRecord)
    #expect(problem.flatMap { ControllerRecordSet.problemCode($0) } == .invalidControllerRecord)
  }

  @Test(arguments: [
    #""persona":"Generic","colour":1"#,
    #""persona":7"#,
    #""persona":"Generic","match":{"vendorID":"1","productID":2}"#,
    #""persona":"Generic","match":{"vendorID":1,"productID":2,"colour":1}"#,
  ])
  func fileThatIsNotSchemaIsRefusedWithE5007(members: String) {
    let document = "{\(Self.header),\(members)}"
    let problem = #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: document),
        source: .unnamed,
        requiresMatch: false
      )
    }
    #expect(problem?.code == .invalidControllerRecord)
  }

  @Test
  func arrayRefusedWithE5007() {
    let problem = #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: "[]"),
        source: .unnamed,
        requiresMatch: false
      )
    }
    #expect(problem?.code == .invalidControllerRecord)
  }

  @Test
  func textNoPropertyListRefusedWithDocumentFormCode() {
    let problem = #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: "{"),
        source: .unnamed,
        requiresMatch: false
      )
    }
    #expect(problem?.code == .invalidDocumentForm)
  }

  @Test
  func kindOfAnotherDocumentIsRefusedWithE5001() {
    let document =
      #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"Controller","colour":1}"#
    let problem = #expect(throws: DocumentHeaderProblem.self) {
      try VirtualDevice.decode(
        PropertyListFixture.bytes(json: document),
        source: .file("a.plist"),
        requiresMatch: false
      )
    }
    #expect(problem?.code == .unsupportedAPIVersion)
  }

  @Test
  func selectionIsDecodedWithItsMatch() throws {
    let document =
      "{\(Self.header),\"persona\":\"Generic\",\"match\":{\"vendorID\":1,\"productID\":2}}"
    let device = try VirtualDevice.decode(
      PropertyListFixture.bytes(json: document),
      source: .unnamed,
      requiresMatch: true
    )
    #expect(device.match == .init(vendorID: 1, productID: 2, unit: nil))
  }
}
