import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The record `ojd record draft` builds from the interfaces of a connected device, served or not.
struct ControllerRecordDraftDeviceTests {
  /// The GameSir G7 Pro dongle of #63: interface 0 is a HID gamepad (usage page 1, usage 5, two
  /// endpoints), interface 1 a HID interface with a vendor usage.
  private static func dongle(model: ControllerModelID) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          interfaceClass: 3,
          interfaceSubclass: 0,
          interfaceProtocol: 0,
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(
            primaryUsage: HIDUsageSignature(usagePage: 1, usage: 5),
            reportDescriptor: Data(GamepadHIDDescriptor.descriptor)
          )
        ),
        PhysicalInterfaceSignature(
          interfaceNumber: 1,
          interfaceClass: 3,
          interfaceSubclass: 0,
          interfaceProtocol: 0,
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(primaryUsage: HIDUsageSignature(usagePage: 0xFF00, usage: 1))
        ),
      ]
    )
  }

  /// A device with only vendor-class interfaces; the first signature appears twice.
  private static func vendorDevice(model: ControllerModelID) -> PhysicalDevice {
    func interface(_ number: UInt8, _ subclass: UInt8, _ proto: UInt8) -> PhysicalInterfaceSignature
    {
      PhysicalInterfaceSignature(
        interfaceNumber: number,
        interfaceClass: 255,
        interfaceSubclass: subclass,
        interfaceProtocol: proto,
        hostTransport: .usb
      )
    }
    return PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      interfaces: [interface(0, 93, 1), interface(1, 93, 2), interface(2, 93, 1)]
    )
  }

  private static let unbundled = ControllerModelID(vendorID: 0x1234, productID: 0x5678)
  /// The dongle's model, whose bundled record holds one `XboxGIP` mode.
  private static let gameSir = ControllerModelID(vendorID: 0x3537, productID: 0x1022)

  private func tree(_ draft: ControllerRecordDraft) throws -> [String: Any] {
    try #require(PropertyListFixture.tree(draft.document) as? [String: Any])
  }

  @Test
  func theDongleOfIssue63GetsAPatchThatAddsAHIDDescriptorMode() throws {
    let draft = try #require(
      ControllerRecordDraft(model: Self.gameSir, device: Self.dongle(model: Self.gameSir))
    )
    #expect(draft.operation == .patch && draft.family == .hidDescriptor)
    #expect(draft.missingSections.isEmpty)
    let document = try tree(draft)
    let modes = try #require((document["patch"] as? [String: Any])?["modes"] as? [[String: Any]])
    #expect(modes.count == 1)
    #expect(modes.first?["id"] as? String == "hid")
    #expect((modes.first?["protocol"] as? [String: Any])?["family"] as? String == "HIDDescriptor")
    let match = (modes.first?["match"] as? [String: Any])?["interfaceSignature"] as? [String: Int]
    #expect(
      match == [
        "interfaceClass": 3, "interfaceSubclass": 0, "interfaceProtocol": 0, "usagePage": 1,
        "usage": 5,
      ]
    )
    #expect(document["remove"] == nil)

    let record = try #require(try ControllerRecordSet.validate(draft.document).record)
    let merged = try #require(PropertyListFixture.tree(Data(record.text.utf8)) as? [String: Any])
    let mergedModes = try #require(merged["modes"] as? [[String: Any]])
    #expect(mergedModes.compactMap { $0["id"] as? String } == ["default", "hid"])
    #expect(
      mergedModes.compactMap { ($0["protocol"] as? [String: Any])?["family"] as? String }
        == ["XboxGIP", "HIDDescriptor"]
    )
  }

  @Test
  func aNewModelWithAHIDGamepadGetsAHIDDescriptorController() throws {
    let draft = try #require(
      ControllerRecordDraft(model: Self.unbundled, device: Self.dongle(model: Self.unbundled))
    )
    #expect(draft.operation == .add && draft.family == .hidDescriptor)
    #expect(draft.missingSections.isEmpty)
    let record = try #require(try ControllerRecordSet.validate(draft.document).record)
    #expect(record.family == "HIDDescriptor")
  }

  @Test
  func aVendorClassDeviceGetsTheIdentityAndOneModePerInterfaceSignature() throws {
    let draft = try #require(
      ControllerRecordDraft(model: Self.unbundled, device: Self.vendorDevice(model: Self.unbundled))
    )
    #expect(draft.operation == .add)
    #expect(draft.missingSections == ["input"])
    let document = try tree(draft)
    #expect(document["vendorID"] as? Int == 0x1234 && document["productID"] as? Int == 0x5678)
    let modes = try #require(document["modes"] as? [[String: Any]])
    #expect(
      modes.compactMap { $0["id"] as? String } == ["interface-255-93-1", "interface-255-93-2"]
    )
    let signatures = modes.compactMap {
      ($0["match"] as? [String: Any])?["interfaceSignature"] as? [String: Int]
    }
    #expect(signatures.map { $0["interfaceProtocol"] } == [1, 2])
    #expect(signatures.allSatisfy { $0["interfaceClass"] == 255 && $0["interfaceSubclass"] == 93 })
  }

  /// Everything but the named missing input section passes `ojd record validate`: the one
  /// failure is the input layout the draft's family needs.
  @Test
  func theVendorClassDraftFailsValidationOnlyOnTheInputSection() throws {
    let draft = try #require(
      ControllerRecordDraft(model: Self.unbundled, device: Self.vendorDevice(model: Self.unbundled))
    )
    let problem = #expect(throws: (any Error).self) {
      _ = try ControllerRecordSet.validate(draft.document)
    }
    #expect("\(String(describing: problem))".contains("needs the record's input layout"))
  }

  @Test
  func aDeviceWithNoInterfaceGetsNoDraft() {
    let device = PhysicalDevice(
      vendorID: Self.unbundled.vendorID,
      productID: Self.unbundled.productID
    )
    #expect(ControllerRecordDraft(model: Self.unbundled, device: device) == nil)
  }
}
