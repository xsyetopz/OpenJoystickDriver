import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SDLMappingBindingTests {
  private static let catalog = DeviceCatalog()

  private func classify(_ device: PhysicalDevice) -> ProtocolClassification {
    ProtocolClassifier.classify(device, backend: .hid, catalog: Self.catalog)
  }

  private func binding(_ device: PhysicalDevice) throws -> ProtocolBinding {
    guard case .bound(let binding) = classify(device) else {
      Issue.record("expected a binding")
      throw BindingMissing()
    }
    return binding
  }

  private struct BindingMissing: Error {}

  private func fixture(_ name: String) throws -> SDLMappingFixture {
    try #require(SDLMappingFixture.all()[name])
  }

  private func hidDevice(
    _ vendorID: UInt16,
    _ productID: UInt16,
    version: UInt16 = 0x0100,
    descriptor: [UInt8] = GamepadHIDDescriptor.descriptor,
    elements: [HIDElementDescription] = []
  ) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: vendorID,
      productID: productID,
      deviceRelease: version,
      productName: "8BitDo M30",
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(reportDescriptor: Data(descriptor), elements: elements)
        )
      ]
    )
  }

  @Test
  func unrecordedPadWithALineBindsWithTheDatabaseRule() throws {
    let fixture = try fixture("8bitdo-m30")
    let binding = try binding(fixture.physicalDevice)
    #expect(binding.protocolID == .hidDescriptor)
    #expect(binding.rule == .sdlGameControllerDB)
    #expect(binding.matchedPredicates == [.hidDescriptorContract])
    let mapping = try #require(binding.inputMapping)
    #expect(mapping.source == .sdlGameControllerDB)
    #expect(mapping.match == .guidWithoutNameCRC)
    #expect(mapping.guid == "03000000c82d00005106000000010000")
    #expect(mapping.unmapped.isEmpty && mapping.rejection == nil)
  }

  @Test
  func theDriverReadsTheConvertedMap() throws {
    let fixture = try fixture("backbone-one")
    let binding = try binding(fixture.physicalDevice)
    let driver = try ProtocolDriverRegistry().makeDriver(
      for: binding,
      model: ControllerModelID(vendorID: 0x358A, productID: 0x0201),
      claimed: nil
    ).get()
    let hid = try #require(driver as? HIDDescriptorDriver)
    #expect(hid.usageMap.rendered.sorted() == fixture.expected.sorted())
    #expect(binding.inputMapping?.unmapped == fixture.expectedUnmapped)
  }

  @Test
  func padWithARecordIgnoresTheDatabase() throws {
    let device = hidDevice(0x2DC8, 0x301B, version: 1)
    #expect(SDLGameControllerDatabase.bundled.match(for: device) != nil)
    let binding = try binding(device)
    #expect(binding.rule == .catalogRecord)
    #expect(binding.inputMapping == .record)
  }

  @Test
  func padThatFailsTheDescriptorContractStaysUnboundAndNotesTheLine() throws {
    let vendorOnly: [UInt8] = [
      0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x75, 0x08, 0x95, 0x3F, 0x81, 0x02, 0xC0,
    ]
    let device = hidDevice(0x2DC8, 0x0651, descriptor: vendorOnly)
    guard case .unsupported(let reason, let rejected) = classify(device) else {
      Issue.record("expected unsupported")
      return
    }
    #expect(reason == .descriptorContractMismatch)
    let mapping = try #require(rejected?.inputMapping)
    #expect(mapping.source == InputMapping.Source.none)
    #expect(mapping.match == .guidWithoutNameCRC)
    #expect(mapping.guid == "03000000c82d00005106000000010000")
  }

  @Test
  func padWithoutALineReportsTheStandardMap() throws {
    let binding = try binding(hidDevice(0x1234, 0x5678))
    #expect(binding.rule == .hidDescriptor)
    let mapping = try #require(binding.inputMapping)
    #expect(mapping.source == .standardHIDUsageMap)
    #expect(mapping.guid != nil && mapping.match == nil)
  }

  @Test
  func lineThatCannotConvertKeepsTheStandardMapAndSaysWhy() throws {
    let binding = try binding(hidDevice(0x2DC8, 0x0651))
    #expect(binding.rule == .hidDescriptor)
    let mapping = try #require(binding.inputMapping)
    #expect(mapping.source == .standardHIDUsageMap)
    #expect(mapping.match == .guidWithoutNameCRC)
    #expect(mapping.rejection?.isEmpty == false)
  }

  @Test
  func theBindingResultCarriesTheMapping() throws {
    let fixture = try fixture("8bitdo-m30")
    let binding = try binding(fixture.physicalDevice)
    let result = ProtocolBindingResult(
      binding: binding,
      interfaces: fixture.physicalDevice.interfaces ?? []
    )
    #expect(result.inputMapping == binding.inputMapping)
    #expect(result.rule == .sdlGameControllerDB)
  }
}
