import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordSetTests {
  private static let recordSchema = ControllerRecordDocument.schemaID
  private static let overrideSchema = ControllerRecordSet.overrideSchemaID
  /// A bundled `xbox.gip` record with no protocol options.
  private static let bundledGIP = ControllerIdentity(vendorID: 0x366C, productID: 0x0005)
  /// A bundled `sony.dualshock4` record, a HID family.
  private static let bundledHID = ControllerIdentity(vendorID: 0x2C22, productID: 0x2000)
  private static let unbundled = ControllerIdentity(vendorID: 0x1234, productID: 0xABCD)

  private static func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  private static func patch(_ identity: ControllerIdentity, set: [String: Any]) throws -> Data {
    try json([
      "$schema": overrideSchema, "operation": "patch", "vendorID": Int(identity.vendorID),
      "productID": Int(identity.productID), "set": set,
    ])
  }

  private static func add(_ identity: ControllerIdentity, family: String) throws -> Data {
    try json([
      "$schema": overrideSchema, "operation": "add",
      "record": [
        "$schema": recordSchema, "vendorID": Int(identity.vendorID),
        "productID": Int(identity.productID), "protocol": ["family": family],
      ],
    ])
  }

  private static func problem(_ data: Data) -> String? {
    do {
      _ = try ControllerRecordSet.validate(data)
      return nil
    } catch { return ControllerRecordSet.problemDescription(error) }
  }

  @Test
  func patchReplacesOnlyItsFieldsAndMarksThemUser() throws {
    let validated = try ControllerRecordSet.validate(
      Self.patch(Self.bundledGIP, set: ["protocol": ["family": "xbox.gip", "keepAlive": false]])
    )
    #expect(validated.operation == .patch)
    #expect(validated.fileName == "366c-0005.json")
    #expect(validated.record.fieldLayers == ["protocol": .user])
    #expect(validated.record.profile.gipKeepAlivePolicy == .disabled)
    #expect(validated.record.usesRawUSB)
    let bundled = try #require(ControllerRecordSet.bundled.records[Self.bundledGIP])
    #expect(bundled.layer == .bundled)
    #expect(bundled.fieldLayers == ["protocol": .bundled])
  }

  @Test
  func addForANewIdentityIsAUserRecord() throws {
    let validated = try ControllerRecordSet.validate(Self.add(Self.unbundled, family: "xbox.gip"))
    #expect(validated.operation == .add)
    #expect(validated.record.identity == Self.unbundled)
    #expect(validated.record.fieldLayers == ["protocol": .user])
    #expect(validated.record.family == "xbox.gip")
  }

  @Test
  func recordsThatDoNotFitTheCatalogAreRejected() throws {
    #expect(
      Self.problem(try Self.add(Self.bundledGIP, family: "xbox.gip"))
        == "366C:0005 is a bundled controller; use a patch to change it"
    )
    #expect(
      Self.problem(try Self.patch(Self.unbundled, set: ["protocol": ["family": "xbox.gip"]]))
        == "1234:ABCD is not a bundled controller; use an add record"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["protocol": ["family": "xbox.gip"]]))
        == "the patch changes nothing in the bundled record"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledHID, set: ["usb": ["postHandshakeSettleMs": 5]]))
        == "USB overrides require a raw-USB protocol family"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["capabilities": ["rumble": "absent"]]))
        == "set must hold protocol, usb, ownership, output, or input"
    )
    #expect(Self.problem(Data("[]".utf8)) == "the file is not a JSON object")
    let unknownKey = try Self.json([
      "$schema": Self.overrideSchema, "operation": "patch", "vendorID": 0x366C, "productID": 5,
      "set": ["usb": ["postHandshakeSettleMs": 5]], "note": "x",
    ])
    #expect(Self.problem(unknownKey) == "unknown field(s): note")
    let badFamily = try Self.add(Self.unbundled, family: "xbox.unknown")
    #expect(Self.problem(badFamily) == "record.protocol: unknown family xbox.unknown")
  }

  @Test
  func loadAppliesValidFilesAndReportsTheRest() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Self.add(Self.unbundled, family: "xbox.gip").write(
      to: directory.appendingPathComponent("1234-abcd.json")
    )
    try Self.patch(Self.bundledGIP, set: ["usb": ["postHandshakeSettleMs": 5]]).write(
      to: directory.appendingPathComponent("wrong-name.json")
    )
    try Data("{".utf8).write(to: directory.appendingPathComponent("broken.json"))

    let set = ControllerRecordSet.load(userDirectory: directory)
    #expect(
      set.userFiles.map(\.url.lastPathComponent) == [
        "1234-abcd.json", "broken.json", "wrong-name.json",
      ]
    )
    #expect(set.records[Self.unbundled]?.layer == .user)
    #expect(set.records[Self.bundledGIP]?.layer == .bundled)
    #expect(set.problems.map(\.url.lastPathComponent) == ["broken.json", "wrong-name.json"])
    #expect(set.problems.last?.problem == "the file name must be 366c-0005.json")
    #expect(set.records.count == ControllerRecordSet.bundled.records.count + 1)

    let catalog = DeviceCatalog(records: set)
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0xABCD, serialNumber: "S")
    #expect(catalog.record(for: identifier)?.physicalProtocolID == .xboxGIP)
    #expect(
      catalog.rawUSBProfileIdentifiers.contains(
        DeviceIdentifier(vendorID: 0x1234, productID: 0xABCD)
      )
    )
  }

  @Test
  func aMissingDirectoryHoldsNoRecords() {
    let set = ControllerRecordSet.load(
      userDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    )
    #expect(set.userFiles.isEmpty)
    #expect(set.records.count == ControllerRecordSet.bundled.records.count)
  }

  @Test
  func activatingTheSameRecordsChangesNothing() {
    #expect(ControllerRecordSet.bundled.activate().isEmpty)
  }
}
