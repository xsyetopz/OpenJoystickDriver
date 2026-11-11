import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

// A mode with `idle` serves nothing while the mode matches: no traffic and no virtual gamepad.
// Its value names the reason.
struct IdleRecordTests {
  private static let model = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
  private static let receiver = ControllerModelID(vendorID: 0x2DC8, productID: 0x301C)
  private static func defaultMode(idle: String? = nil) -> [String: Any] {
    var mode: [String: Any] = ["id": "default", "protocol": ["family": "HIDDescriptor"]]
    mode["idle"] = idle
    return mode
  }
  private static var idleMode: [String: Any] {
    [
      "id": "unlinked", "protocol": ["family": "HIDDescriptor"], "idle": "NoControllerLinked",
      "match": ["product": "IDLE"],
    ]
  }

  private static func data(_ fields: [String: Any]) throws -> Data {
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID),
      "modes": [defaultMode()],
    ].merging(fields) { $1 }
    return try PropertyListFixture.data(tree: record)
  }

  private static func problem(_ fields: [String: Any]) -> String? {
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

  private static func catalog(_ fields: [String: Any]) throws -> DeviceCatalog {
    let validated = try #require(try ControllerRecordSet.validate(data(fields)).record)
    return DeviceCatalog(
      records: ControllerRecordSet(records: [model: validated], userFiles: [])
    )
  }

  @Test
  func anIdleDefaultModeClassifiesAsItsReasonWithoutABinding() throws {
    let catalog = try Self.catalog(["modes": [Self.defaultMode(idle: "NoControllerLinked")]])
    #expect(catalog.record(for: Self.model)?.idleReason == .noControllerLinked)
    #expect(
      ProtocolClassifier.classify(Self.hidDevice(Self.model), backend: .hid, catalog: catalog)
        == .unsupported(.noControllerLinked)
    )
  }

  @Test
  func theBootloaderReasonClassifiesAsBootloader() throws {
    let catalog = try Self.catalog(["modes": [Self.defaultMode(idle: "Bootloader")]])
    #expect(
      ProtocolClassifier.classify(Self.hidDevice(Self.model), backend: .hid, catalog: catalog)
        == .unsupported(.bootloaderIdentity)
    )
  }

  @Test
  func aSelectedIdleModeIdlesAndTheDefaultModeServes() throws {
    let catalog = try Self.catalog(["modes": [Self.defaultMode(), Self.idleMode]])
    let device = Self.hidDevice(Self.model)
    #expect(catalog.record(for: Self.model)?.idleReason == nil)
    #expect(
      ProtocolClassifier.classify(device, backend: .hid, catalog: catalog, modeID: "unlinked")
        == .unsupported(.noControllerLinked)
    )
    #expect(
      ProtocolClassifier.classify(device, backend: .hid, catalog: catalog)
        != .unsupported(.noControllerLinked)
    )
  }

  @Test
  func aRecordWithoutIdleIsNotIdle() throws {
    #expect(try Self.catalog([:]).record(for: Self.model)?.idleReason == nil)
  }

  @Test
  func eachReasonHasItsOwnExplanation() {
    #expect(ProtocolBindingReason.noControllerLinked.rawValue == "NoControllerLinked")
    #expect(
      ProtocolBindingReason.noControllerLinked.explanationKey
        == "ui.controllers.noControllerLinked"
    )
    #expect(
      ProtocolBindingReason.bootloaderIdentity.explanationKey == "ui.controllers.bootloaderIdentity"
    )
  }

  @Test
  func idleIsAReasonOfTheRecordsModeNotARecordKey() {
    #expect(Self.problem(["idle": "NoControllerLinked"]) != nil)
    #expect(Self.problem(["modes": [Self.defaultMode(idle: "Sleeping")]]) != nil)
    var mode = Self.defaultMode()
    mode["idle"] = true
    #expect(Self.problem(["modes": [mode]]) != nil)
  }

  @Test
  func anIdleModeRefusesASessionAndAnInterface() {
    for extra: (String, Any) in [
      ("session", ["settleMilliseconds": 100]), ("interface", ["first": 0, "last": 0]),
    ] {
      var mode = Self.defaultMode(idle: "NoControllerLinked")
      mode[extra.0] = extra.1
      #expect(Self.problem(["modes": [mode]]) != nil, "\(extra.0)")
    }
  }

  @Test
  func aRecordOfOnlyIdleModesRefusesASectionThatServesControls() {
    let sections: [String: Any] = [
      "input": ["hidUsageMap": ["usages": [["kind": "Hat", "page": 1, "usage": 57]]]],
      "tuning": ["stickDeadzone": 0.1],
      "server": "OJD",
      "capabilities": ["rumble": "Absent"],
    ]
    for (section, value) in sections {
      let fields: [String: Any] = [
        "modes": [Self.defaultMode(idle: "NoControllerLinked")], section: value,
      ]
      #expect(Self.problem(fields) != nil, "\(section)")
    }
  }

  @Test
  func aRecordWithAnIdleModeAndAServingModeKeepsItsSections() {
    #expect(
      Self.problem(["modes": [Self.defaultMode(), Self.idleMode], "server": "OJD"]) == nil
    )
  }

  private static func receiverDevice(product: String) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: receiver.vendorID,
      productID: receiver.productID,
      productName: product,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
  }

  private static func selection(product: String) async -> ControllerModeSelection {
    await ProtocolDriverRegistry().selectMode(
      of: receiver,
      backend: .hid,
      reader: UnreadableModeProbeReader(),
      device: receiverDevice(product: product)
    )
  }

  @Test
  func theBundledReceiverIdlesWhileItsProductStringIsIDLE() async throws {
    let catalog = DeviceCatalog()
    let modeID = try #require(await Self.selection(product: "IDLE").modeID)
    #expect(catalog.record(for: Self.receiver, modeID: modeID)?.idleReason == .noControllerLinked)
    #expect(
      ProtocolClassifier.classify(
        Self.receiverDevice(product: "IDLE"),
        backend: .hid,
        catalog: catalog,
        modeID: modeID
      ) == .unsupported(.noControllerLinked)
    )
  }

  @Test
  func theBundledReceiverServesWhileAPadIsLinked() async {
    let catalog = DeviceCatalog()
    let product = "8BitDo Ultimate 2C Wireless Controller"
    let selection = await Self.selection(product: product)
    #expect(selection.modeID == nil)
    #expect(catalog.record(for: Self.receiver)?.idleReason == nil)
    guard
      case .bound(let binding) = ProtocolClassifier.classify(
        Self.receiverDevice(product: product),
        backend: .hid,
        catalog: catalog,
        modeID: selection.modeID
      )
    else {
      Issue.record("the linked receiver is not bound")
      return
    }
    #expect(binding.protocolID == .hidDescriptor)
  }
}
