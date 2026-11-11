import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A family that only a description document names: the document sets `defaults.input.layouts`,
/// and `ReportLayoutDriver` decodes its reports.
struct DocumentedFamilyTests {
  static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

  /// The Flydigi description under `name`, with a display name and no interface signatures.
  static func description(named name: String) throws -> Data {
    let source = repository.appendingPathComponent("Resources/Protocols/vendor-flydigi.plist")
    var tree = try #require(try PropertyListFixture.tree(Data(contentsOf: source)) as? [String: Any])
    tree["family"] = name
    tree["displayName"] = "Acme Pad"
    tree["interfaceSignatures"] = nil
    return try PropertyListFixture.data(tree: tree)
  }

  @Test
  func aDescriptionDocumentBindsAControllerAndDecodesItsReports() throws {
    let name = "VendorAcmeBinding"
    let description = try ProtocolDescription.decode(
      Self.description(named: name),
      fileName: "\(name).plist"
    )
    DocumentedProtocolFamilies.register([description], owner: URL(fileURLWithPath: "/\(name)"))
    let family = try #require(PhysicalProtocolID(rawValue: name))
    #expect(family.displayName == "Acme Pad")
    #expect(!PhysicalProtocolID.allCases.contains(family))

    let model = ControllerModelID(vendorID: 0x1234, productID: 0xAC01)
    let record = try PropertyListFixture.data(tree: [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID),
      "modes": [["id": "default", "protocol": ["family": name]]],
    ])
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-documented-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try record.write(to: directory.appendingPathComponent("1234-ac01.plist"))
    let set = ControllerRecordSet.load(userDirectory: directory)
    #expect(set.problems.isEmpty)

    let device = PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .usb)]
    )
    guard
      case .bound(let binding) = ProtocolClassifier.classify(
        device,
        backend: .hid,
        catalog: DeviceCatalog(records: set)
      )
    else {
      Issue.record("the documented family did not bind")
      return
    }
    #expect(binding.protocolID == family)
    let driver = try ProtocolDriverRegistry().makeDriver(
      for: binding,
      model: model,
      claimed: nil
    ).get()
    var report = Data([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    _ = try driver.parseReport(report)
    report[9] = 0x10
    #expect(try driver.parseReport(report).contains(.press(.south)))
  }
}
