import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A controller no record names: each rule that binds it, and the driver and input it gets.
struct UnrecordedControllerTests {
  private let registry = ProtocolDriverRegistry()
  private let unrecorded = ControllerModelID(vendorID: 0x1234, productID: 0x5678)

  private struct NotBound: Error {}

  private func bound(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend = .rawUSB
  ) throws -> ProtocolBinding {
    let classification = registry.classify(device, backend: backend)
    guard case .bound(let binding) = classification else {
      Issue.record("did not bind: \(classification)")
      throw NotBound()
    }
    return binding
  }

  /// A claim whose interface has the family triple and the profile's interrupt endpoint pair.
  private func claim(
    for binding: ProtocolBinding,
    triple: (UInt8, UInt8, UInt8)
  ) throws -> USBTransportResolution {
    let profile = try #require(registry.runtimeProfile(for: binding)).transportProfile
    let interface = PhysicalInterfaceSignature(
      interfaceNumber: profile.interfaceNumber,
      alternateSetting: profile.alternateSetting,
      interfaceClass: triple.0,
      interfaceSubclass: triple.1,
      interfaceProtocol: triple.2,
      endpoints: [
        PhysicalEndpointSignature(
          address: profile.inputEndpoint,
          direction: .in,
          transferType: .interrupt
        ),
        PhysicalEndpointSignature(
          address: profile.outputEndpoint,
          direction: .out,
          transferType: .interrupt
        ),
      ]
    )
    return USBTransportResolution(
      profile: profile,
      physicalDevice: PhysicalDevice(
        vendorID: unrecorded.vendorID,
        productID: unrecorded.productID,
        configurationValue: 1,
        interfaces: [interface]
      )
    )
  }

  private func usbDevice(_ triple: (UInt8, UInt8, UInt8)) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: unrecorded.vendorID,
      productID: unrecorded.productID,
      configurationValue: 1,
      interfaces: [registryInterface(0, triple.0, triple.1, triple.2)]
    )
  }

  // MARK: - Interface signatures

  @Test
  func anXUSBInterfaceSignatureBindsTheFamilyAndItsDriverReadsAReport() throws {
    let triple: (UInt8, UInt8, UInt8) = (0xFF, 0x5D, 0x01)
    #expect(registry.record(for: unrecorded) == nil)
    let binding = try bound(usbDevice(triple))
    #expect(binding.id.rawValue == "XboxXUSB:Wired")
    #expect(binding.rule == .interfaceSignature)
    #expect(binding.record == nil)
    let driver = try registry.makeDriver(
      for: binding,
      model: unrecorded,
      claimed: try claim(for: binding, triple: triple)
    ).get()
    let xusb = try #require(driver as? XUSBDriver)
    // South is bit 12 of the button word (bytes 2 and 3).
    var report = [UInt8](repeating: 0, count: 20)
    report[1] = 0x14
    report[3] = 0x10
    let event = try xusb.parseReport(Data(report))
    #expect(event?.state.pressed.contains(.south) == true)
  }

  @Test
  func aGIPInterfaceSignatureBindsTheFamilyAndItsDriverReadsAReport() throws {
    let triple: (UInt8, UInt8, UInt8) = (0xFF, 0x47, 0xD0)
    #expect(registry.record(for: unrecorded) == nil)
    let binding = try bound(usbDevice(triple))
    #expect(binding.id.rawValue == "XboxGIP:USB")
    #expect(binding.rule == .interfaceSignature)
    #expect(binding.record == nil)
    let driver = try registry.makeDriver(
      for: binding,
      model: unrecorded,
      claimed: try claim(for: binding, triple: triple)
    ).get()
    let gip = try #require(driver as? GIPDriver)
    // Command 0x20 (input), 14 payload bytes; the Menu bit is bit 2 of the first byte.
    var report: [UInt8] = [0x20, 0x00, 0x01, 0x0E]
    report += [0x04] + [UInt8](repeating: 0, count: 13)
    let event = try gip.parseReport(Data(report))
    #expect(event?.state.pressed.contains(.start) == true)
  }

  // MARK: - HID pads

  private func hidDevice(_ vendorID: UInt16, _ productID: UInt16) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: vendorID,
      productID: productID,
      deviceRelease: 0x0100,
      productName: "Pad",
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(
            reportDescriptor: Data(GamepadHIDDescriptor.descriptor),
            elements: []
          )
        )
      ]
    )
  }

  private func hidDriver(
    for device: PhysicalDevice,
    model: ControllerModelID
  ) throws -> (ProtocolBinding, HIDDescriptorDriver) {
    let binding = try bound(device, backend: .hid)
    let driver = try registry.makeDriver(for: binding, model: model, claimed: nil).get()
    return (binding, try #require(driver as? HIDDescriptorDriver))
  }

  private func press(_ driver: HIDDescriptorDriver, usage: UInt32) -> ControllerState? {
    let value = HIDElementValue(
      usagePage: 9,
      usage: usage,
      logicalMinimum: 0,
      logicalMaximum: 1,
      integerValue: 1,
      reportID: nil
    )
    return driver.parse(elementValue: value, receivedAt: MonotonicTimestamp(nanoseconds: 0))?.state
  }

  @Test
  func aDatabaseLineMapsAPadWithNoRecord() throws {
    let fixture = try #require(SDLMappingFixture.all()["8bitdo-m30"])
    let model = ControllerModelID(vendorID: 0x2DC8, productID: 0x5106)
    #expect(registry.record(for: model) == nil)
    let (binding, driver) = try hidDriver(for: fixture.physicalDevice, model: model)
    #expect(binding.rule == .sdlGameControllerDB)
    #expect(binding.inputMapping?.source == .sdlGameControllerDB)
    #expect(driver.usageMap.rendered.sorted() == fixture.expected.sorted())
    // The line maps usage 9/2 to South and 9/1 to East.
    #expect(press(driver, usage: 2)?.pressed.contains(.south) == true)
    #expect(press(driver, usage: 1)?.pressed.contains(.east) == true)
  }

  @Test
  func theStandardUsageMapReadsAPadWithNoRecordAndNoLine() throws {
    let model = ControllerModelID(vendorID: 0x1234, productID: 0x5678)
    #expect(registry.record(for: model) == nil)
    let (binding, driver) = try hidDriver(for: hidDevice(0x1234, 0x5678), model: model)
    #expect(binding.rule == .hidDescriptor)
    #expect(binding.inputMapping?.source == .standardHIDUsageMap)
    #expect(press(driver, usage: 1)?.pressed.contains(.south) == true)
    #expect(press(driver, usage: 2)?.pressed.contains(.east) == true)
  }
}
