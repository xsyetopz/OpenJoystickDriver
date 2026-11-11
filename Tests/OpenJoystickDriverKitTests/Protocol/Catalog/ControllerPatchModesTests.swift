import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A patch reaches every record property except the identity, and `patch.modes` merges by `id`.
struct ControllerPatchModesTests {
  private static let identity = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  private static func json(_ text: String) throws -> OrderedJSON {
    try OrderedJSON.parse(Data(text.utf8))
  }

  private static func modes(_ record: OrderedJSON) -> [OrderedJSON] {
    guard case .array(let modes)? = record["modes"] else { return [] }
    return modes
  }

  private static func modeIDs(_ record: OrderedJSON) -> [String] {
    modes(record).compactMap { $0["id"]?.string }
  }

  private static func patch(
    patch: String? = nil,
    remove: [String]? = nil
  ) throws -> ControllerPatch {
    var members: [String] = [
      #""apiVersion": "openjoystickdriver/v1alpha3""#, #""kind": "ControllerPatch""#,
      #""selector": {"vendorID": 4660, "productID": 43981}"#,
    ]
    if let patch { members.append(#""patch": \#(patch)"#) }
    if let remove {
      members.append(
        #""remove": [\#(remove.map { "\"\($0)\"" }.joined(separator: ","))]"#
      )
    }
    return try ControllerPatch.parse(json("{" + members.joined(separator: ",") + "}"))
  }

  private static let twoModes = """
    {"vendorID": 4660, "productID": 43981, "modes": [
      {"id": "default", "protocol": {"family": "XboxGIP"}},
      {"id": "usb-b", "protocol": {"family": "XboxGIP"},
       "match": {"interfaceSignature": {"interfaceClass": 255, "interfaceSubclass": 71,
         "interfaceProtocol": 208, "endpoints": [{"direction": "In", "transferType": "Bulk"}]}}}
    ]}
    """

  @Test
  func aPatchOfOneEndpointOfOneModeKeepsTheOtherModes() throws {
    let patch = try Self.patch(
      patch: """
        {"modes": [{"id": "usb-b", "match": {"interfaceSignature": {"endpoints":
          [{"direction": "In", "transferType": "Interrupt"}]}}}]}
        """
    )
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.twoModes))
    let expected = try Self.json(
      """
      {"vendorID": 4660, "productID": 43981, "modes": [
        {"id": "default", "protocol": {"family": "XboxGIP"}},
        {"id": "usb-b", "protocol": {"family": "XboxGIP"},
         "match": {"interfaceSignature": {"interfaceClass": 255, "interfaceSubclass": 71,
           "interfaceProtocol": 208,
           "endpoints": [{"direction": "In", "transferType": "Interrupt"}]}}}
      ]}
      """
    )
    #expect(result == expected)
  }

  @Test
  func aPatchWithANewModeIDAddsAMode() throws {
    let patch = try Self.patch(
      patch: """
        {"modes": [{"id": "hid", "protocol": {"family": "HIDDescriptor"},
          "match": {"interfaceSignature": {"interfaceClass": 3, "interfaceSubclass": 0,
            "interfaceProtocol": 0}}}]}
        """
    )
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.twoModes))
    let ids = Self.modeIDs(result)
    #expect(ids == ["default", "usb-b", "hid"])
  }

  @Test
  func theRemovePathModesIDRemovesOneMode() throws {
    let patch = try Self.patch(remove: ["modes.usb-b"])
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.twoModes))
    #expect(Self.modeIDs(result) == ["default"])
  }

  @Test
  func theRemovePathModesIDOfAnAbsentModeRemovesNothing() throws {
    let patch = try Self.patch(remove: ["modes.gone"])
    let record = try Self.json(Self.twoModes)
    #expect(ControllerPatchMerge.apply(patch, to: record) == record)
  }

  @Test
  func aRemovedModeCanBeAddedAgainByTheSamePatch() throws {
    let patch = try Self.patch(
      patch: #"{"modes": [{"id": "usb-b", "protocol": {"family": "HIDDescriptor"}}]}"#,
      remove: ["modes.usb-b"]
    )
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.twoModes))
    #expect(Self.modes(result).count == 2)
    #expect(Self.modes(result).last?["protocol"] == (try Self.json(#"{"family": "HIDDescriptor"}"#)))
    #expect(Self.modes(result).last?["match"] == nil)
  }

  @Test
  func aPatchSetsCapabilitiesAndTheIdleOfAMode() throws {
    let patch = try Self.patch(
      patch: #"{"capabilities": {"rumble": "Absent"}, "modes": [{"id": "usb-b", "idle": "Bootloader"}]}"#
    )
    let result = ControllerPatchMerge.apply(patch, to: try Self.json(Self.twoModes))
    #expect(result["capabilities"] == (try Self.json(#"{"rumble": "Absent"}"#)))
    #expect(Self.modes(result).last?["idle"] == .string("Bootloader"))
  }

  @Test
  func aPatchOfARecordLevelIdleIsRefused() {
    #expect(throws: ControllerRecordProblem.self) {
      _ = try Self.patch(patch: #"{"idle": "NoControllerLinked"}"#)
    }
    #expect(throws: ControllerRecordProblem.self) { _ = try Self.patch(remove: ["idle"]) }
  }

  @Test
  func aPatchThatSetsTheIdentityIsRefused() throws {
    for key in ["vendorID", "productID", "apiVersion", "kind"] {
      #expect(throws: ControllerRecordProblem.self, "\(key)") {
        _ = try Self.patch(patch: #"{"\#(key)": 1}"#)
      }
    }
  }

  @Test
  func aRemovePathNamesAModeByAValidIDOnly() throws {
    for path in ["modes.", "modes.a.b", "modes.Bad_ID", "modes.1a", "identity", "vendorID"] {
      #expect(throws: ControllerRecordProblem.self, "\(path)") {
        _ = try Self.patch(remove: [path])
      }
    }
  }

  /// The patch #63 needs for `3537:1022`: the bundled record keeps its `XboxGIP` mode and its
  /// rumble capability and gains a `HIDDescriptor` mode matched on the dongle's HID interface.
  @Test
  func thePatchOfTheGameSirDongleGivesARecordThatPassesTheRecordRules() throws {
    let model = ControllerModelID(vendorID: 0x3537, productID: 0x1022)
    let patch = try Self.patch(
      patch: """
        {"modes": [{"id": "hid", "protocol": {"family": "HIDDescriptor"},
          "match": {"interfaceSignature": {"interfaceClass": 3, "interfaceSubclass": 0,
            "interfaceProtocol": 0}}}]}
        """
    )
    let bundled = try #require(ControllerRecordSet.bundled.records[model]?.document)
    let record = try OrderedJSON(document: bundled, file: "record")
    let result = ControllerPatchMerge.apply(patch, to: record)
    let document = try JSONDecoder().decode(
      ControllerRecordDocument.self,
      from: result.formattedData()
    )
    #expect(document.modes.map(\.id) == ["default", "hid"])
    #expect(document.capabilities.rumbleAbsent)
  }

  @Test
  func aRecordOfTwoDriversHoldsACapabilityOnlyIfSomeModeDriverDeclaresIt() throws {
    func decode(_ family: String, capabilities: String) throws -> ControllerRecordDocument {
      try JSONDecoder().decode(
        ControllerRecordDocument.self,
        from: Data(
          """
          {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "Controller",
           "vendorID": 4660, "productID": 43981, "capabilities": \(capabilities),
           "modes": [{"id": "default", "protocol": {"family": "XboxGIP"}},
             {"id": "hid", "protocol": {"family": "\(family)"},
              "match": {"interfaceSignature": {"interfaceClass": 3, "interfaceSubclass": 0,
                "interfaceProtocol": 0}}}]}
          """.utf8
        )
      )
    }
    #expect(try decode("HIDDescriptor", capabilities: #"{"rumble": "Absent"}"#).modes.count == 2)
    #expect(throws: DecodingError.self) {
      _ = try decode("HIDDescriptor", capabilities: #"{"present": ["Share"]}"#)
    }
  }
}
