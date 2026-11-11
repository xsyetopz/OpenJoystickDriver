import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The bundled records of the 8BitDo bootloader identities idle them with the reason `Bootloader`,
/// and no user or package document changes that.
struct BootloaderRecordTests {
  private static let identities: [UInt16] = [0x3208, 0x5750]
  private static let refusalKey = "error.E5007.userFile.bootloaderController"
  private static let layers: [ControllerRecordLayer] = [.user, .package]

  private static func model(_ productID: UInt16) -> ControllerModelID {
    ControllerModelID(vendorID: 0x2DC8, productID: productID)
  }

  private static func controllerFile(_ productID: UInt16) throws -> Data {
    try PropertyListFixture.data(
      tree: [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": 0x2DC8, "productID": Int(productID),
        "modes": [["id": "default", "protocol": ["family": "HIDDescriptor"]]],
      ]
    )
  }

  private static func patchFile(_ productID: UInt16, patch: [String: Any]) throws -> Data {
    try PropertyListFixture.data(
      tree: [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": "ControllerPatch",
        "selector": ["vendorID": 0x2DC8, "productID": Int(productID)], "patch": patch,
      ]
    )
  }

  private static func refusalKey(of data: Data, layer: ControllerRecordLayer) -> String? {
    do {
      _ = try ControllerRecordSet.validate(data, layer: layer)
      return nil
    } catch { return (error as? ControllerRecordProblem)?.key }
  }

  @Test(arguments: identities)
  func theBundledRecordIdlesWithTheBootloaderReason(productID: UInt16) throws {
    let record = try #require(DeviceCatalog().record(for: Self.model(productID)))
    #expect(record.idleReason == .bootloader)
    #expect(record.modes.isEmpty)
  }

  @Test(arguments: identities)
  func aGamepadDescriptorDoesNotBindTheBootloaderIdentity(productID: UInt16) {
    let device = PhysicalDevice(
      vendorID: 0x2DC8,
      productID: productID,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
    for backend in [DeviceAccessBackend.hid, .rawUSB] {
      #expect(
        ProtocolClassifier.classify(device, backend: backend, catalog: DeviceCatalog())
          == .unsupported(.bootloaderIdentity)
      )
    }
  }

  @Test
  func onlyTheTwoBootloaderIdentitiesIdleAsBootloaders() {
    let catalog = DeviceCatalog()
    let bootloaders = catalog.documents.keys.filter {
      catalog.record(for: $0)?.idleReason == .bootloader
    }
    #expect(Set(bootloaders) == Set(Self.identities.map(Self.model)))
  }

  @Test
  func theProductIDOfAnotherVendorIsNotABootloader() {
    let device = PhysicalDevice(
      vendorID: 0x1234,
      productID: 0x3208,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
    #expect(
      ProtocolClassifier.classify(device, backend: .hid, catalog: DeviceCatalog())
        != .unsupported(.bootloaderIdentity)
    )
  }

  @Test(arguments: identities, layers)
  func aControllerFileForTheIdentityIsRefused(productID: UInt16, layer: ControllerRecordLayer)
    throws
  {
    let data = try Self.controllerFile(productID)
    #expect(Self.refusalKey(of: data, layer: layer) == Self.refusalKey)
  }

  @Test(arguments: identities, layers)
  func aPatchThatServesTheIdentityIsRefused(productID: UInt16, layer: ControllerRecordLayer)
    throws
  {
    let data = try Self.patchFile(
      productID,
      patch: ["modes": [["id": "default", "protocol": ["family": "HIDDescriptor"]]]]
    )
    #expect(Self.refusalKey(of: data, layer: layer) == Self.refusalKey)
  }

  @Test
  func theUserDirectoryListsTheRefusedFileAndKeepsTheBundledRecord() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-bootloader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = Self.model(0x3208)
    try Self.controllerFile(0x3208).write(
      to: directory.appendingPathComponent(ControllerRecordSet.fileName(for: model))
    )
    let set = ControllerRecordSet.load(userDirectory: directory)
    #expect(set.problems.count == 1)
    #expect(set.records[model]?.layer == .bundled)
    #expect(DeviceCatalog(records: set).record(for: model)?.idleReason == .bootloader)
  }
}
