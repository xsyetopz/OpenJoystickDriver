import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A record with `idle: true` names an identity OJD recognizes and serves nothing: no traffic and
/// no virtual gamepad, with the reason `IdleIdentity`.
struct IdleRecordTests {
  private static let model = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
  private static let receiver = ControllerModelID(vendorID: 0x2DC8, productID: 0x301C)
  private static var defaultMode: [String: Any] {
    ["id": "default", "protocol": ["family": "HIDDescriptor"]]
  }

  private static func data(_ fields: [String: Any]) throws -> Data {
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID),
      "modes": [defaultMode],
    ].merging(fields) { $1 }
    return try PropertyListFixture.data(tree: record)
  }

  private static func problem(_ fields: [String: Any]) throws -> String? {
    do {
      _ = try ControllerRecordSet.validate(data(fields))
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func hidDevice(_ model: ControllerModelID) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .usb)]
    )
  }

  @Test
  func anIdleRecordClassifiesAsIdleIdentityWithoutABinding() throws {
    let validated = try #require(
      try ControllerRecordSet.validate(Self.data(["idle": true])).record
    )
    #expect(validated.profile.isIdle)
    let catalog = DeviceCatalog(
      records: ControllerRecordSet(records: [Self.model: validated], userFiles: [])
    )
    let result = ProtocolClassifier.classify(
      Self.hidDevice(Self.model),
      backend: .hid,
      catalog: catalog
    )
    #expect(result == .unsupported(.idleIdentity))
  }

  @Test
  func aRecordWithoutIdleIsNotIdle() throws {
    let validated = try #require(try ControllerRecordSet.validate(Self.data([:])).record)
    #expect(!validated.profile.isIdle)
  }

  @Test
  func theReasonHasItsOwnExplanation() {
    #expect(ProtocolBindingReason.idleIdentity.rawValue == "IdleIdentity")
    #expect(ProtocolBindingReason.idleIdentity.explanationKey == "ui.controllers.idleIdentity")
  }

  @Test
  func idleOnlyHasTheValueTrue() throws {
    #expect(try Self.problem(["idle": false]) != nil)
    #expect(try Self.problem(["idle": "yes"]) != nil)
  }

  @Test
  func anIdleRecordRefusesASectionThatServesControls() throws {
    let sections: [String: Any] = [
      "input": ["hidUsageMap": ["usages": [["kind": "Hat", "page": 1, "usage": 57]]]],
      "tuning": ["stickDeadzone": 0.1],
      "server": "OJD",
      "capabilities": ["rumble": false],
    ]
    for (section, value) in sections {
      #expect(try Self.problem(["idle": true, section: value]) != nil, "\(section)")
    }
  }

  @Test
  func anIdleRecordRefusesAModeThatIsNotTheOnlyDefault() throws {
    let other: [String: Any] = [
      "id": "other", "protocol": ["family": "HIDDescriptor"],
      "match": ["product": "Receiver"],
    ]
    #expect(try Self.problem(["idle": true, "modes": [Self.defaultMode, other]]) != nil)
    #expect(try Self.problem(["idle": true, "modes": [other]]) != nil)
  }

  @Test
  func theBundledReceiverIdentityServesNothing() throws {
    let catalog = DeviceCatalog()
    let record = try #require(catalog.record(for: Self.receiver))
    #expect(record.isIdle)
    #expect(record.hidUsageMap == nil)
    #expect(
      ProtocolClassifier.classify(Self.hidDevice(Self.receiver), backend: .hid, catalog: catalog)
        == .unsupported(.idleIdentity)
    )
  }
}
