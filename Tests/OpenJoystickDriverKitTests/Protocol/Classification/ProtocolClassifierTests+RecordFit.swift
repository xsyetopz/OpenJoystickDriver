import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A record whose modes fit no interface of the device falls back to the `HIDDescriptor`
/// rule when a HID interface meets that contract.
extension ProtocolClassifierTests {
  private static let dongle = ControllerModelID(vendorID: 0x3537, productID: 0x1022)

  private func padInterface(_ number: UInt8) -> PhysicalInterfaceSignature {
    PhysicalInterfaceSignature(
      interfaceNumber: number,
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      hostTransport: .usb,
      accessBackend: .hid,
      hidLayout: HIDLayoutSummary(
        primaryUsage: HIDUsageSignature(usagePage: 1, usage: 5),
        reportDescriptor: gamepad
      )
    )
  }

  private func vendorInterface(_ number: UInt8) -> PhysicalInterfaceSignature {
    PhysicalInterfaceSignature(
      interfaceNumber: number,
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      hostTransport: .usb,
      accessBackend: .hid,
      hidLayout: HIDLayoutSummary(
        primaryUsage: HIDUsageSignature(usagePage: 0xFF00, usage: 1),
        reportDescriptor: vendorOnly
      )
    )
  }

  private func fitCatalog(
    server: String?,
    family: String,
    interface: [String: Int]?,
    idle: String? = nil,
    match: [String: Any]? = nil
  ) throws -> DeviceCatalog {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-record-fit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var mode: [String: Any] = [
      "id": match == nil ? "default" : "vendor", "protocol": ["family": family],
    ]
    mode["match"] = match
    mode["interface"] = interface
    mode["idle"] = idle
    var tree: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 0x1234, "productID": 0xAC02, "modes": [mode],
    ]
    tree["server"] = server
    try PropertyListFixture.data(tree: tree)
      .write(to: directory.appendingPathComponent("1234-ac02.plist"))
    let set = ControllerRecordSet.load(userDirectory: directory)
    #expect(set.problems.isEmpty)
    return DeviceCatalog(records: set)
  }

  @Test
  func recordFitsNoInterfaceFallsBackToHIDDescriptor() throws {
    let device = PhysicalDevice(
      vendorID: Self.dongle.vendorID,
      productID: Self.dongle.productID,
      interfaces: [vendorInterface(1), padInterface(0)]
    )
    let binding = try bound(classify(device, backend: .hid))
    #expect(binding.protocolID == .hidDescriptor)
    #expect(binding.rule == .hidDescriptor)
    #expect(binding.interfaceNumber == 0)
    #expect(binding.record == nil)
    #expect(binding.inputMapping?.unfitRecordID == "3537-1022")
  }

  @Test
  func fallbackNamesRecordDidNotFitInItsRowText() throws {
    let device = PhysicalDevice(
      vendorID: Self.dongle.vendorID,
      productID: Self.dongle.productID,
      interfaces: [padInterface(0)]
    )
    let mapping = try #require(try bound(classify(device, backend: .hid)).inputMapping)
    let localize: (String) -> String = { Localization().string($0) }
    let text = mapping.rowText(localize: localize)
    #expect(text.contains("HIDDescriptor"))
    #expect(text != InputMapping.standardHIDUsageMap.rowText(localize: localize))
  }

  @Test
  func recordFitsNoInterfaceWithNoHIDInterfaceStaysUnsupported() {
    let vendorClass = usbInterface(0, 0xFF, 0x47, 0xD0)
    for interfaces in [[vendorClass], [vendorInterface(0)]] {
      let device = PhysicalDevice(
        vendorID: Self.dongle.vendorID,
        productID: Self.dongle.productID,
        interfaces: interfaces
      )
      #expect(
        classify(device, backend: .hid)
          == .unsupported(
            .interfaceContractMismatch,
            rejected: ProtocolBindingResult.RejectedCandidate(
              protocolID: .xboxGIP,
              reason: .interfaceContractMismatch,
              catalogRecordID: "3537-1022"
            )
          )
      )
    }
  }

  @Test
  func idleRawUSBModeStaysIdleInsteadOfFallingBack() throws {
    let device = PhysicalDevice(
      vendorID: 0x1234,
      productID: 0xAC02,
      interfaces: [padInterface(0)]
    )
    let idle = try fitCatalog(
      server: nil,
      family: "XboxGIP",
      interface: nil,
      idle: "NoControllerLinked"
    )
    #expect(
      ProtocolClassifier.classify(device, backend: .hid, catalog: idle)
        == .unsupported(.noControllerLinked)
    )
  }

  @Test
  func recordNamesSystemStaysWithMacOS() throws {
    let device = PhysicalDevice(
      vendorID: 0x1234,
      productID: 0xAC02,
      interfaces: [padInterface(0)]
    )
    let range = ["first": 4, "last": 5]
    let open = try fitCatalog(server: nil, family: "SonyDualShock4", interface: range)
    let fallback = try bound(
      ProtocolClassifier.classify(device, backend: .hid, catalog: open)
    )
    #expect(fallback.protocolID == .hidDescriptor)
    #expect(fallback.inputMapping?.unfitRecordID == "1234-ac02")

    let system = try fitCatalog(server: "System", family: "SonyDualShock4", interface: range)
    let kept = try bound(ProtocolClassifier.classify(device, backend: .hid, catalog: system))
    #expect(kept.protocolID == .sonyDualShock4)
    #expect(kept.inputMapping?.unfitRecordID == nil)
  }

  @Test
  func recordWhoseModesMatchNoInterfaceFallsBackToHIDDescriptor() throws {
    let device = PhysicalDevice(
      vendorID: 0x1234,
      productID: 0xAC02,
      interfaces: [padInterface(0)]
    )
    let match: [String: Any] = [
      "interfaceSignature": [
        "interfaceClass": 0xFF, "interfaceSubclass": 0x47, "interfaceProtocol": 0xD0,
      ]
    ]
    let catalog = try fitCatalog(server: nil, family: "XboxGIP", interface: nil, match: match)
    let binding = try bound(ProtocolClassifier.classify(device, backend: .hid, catalog: catalog))
    #expect(binding.protocolID == .hidDescriptor)
    #expect(binding.inputMapping?.unfitRecordID == "1234-ac02")

    let system = try fitCatalog(
      server: "System",
      family: "SonyDualShock4",
      interface: nil,
      match: match
    )
    #expect(
      ProtocolClassifier.classify(device, backend: .hid, catalog: system)
        == .unsupported(.noModeMatched)
    )
  }
}
