import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NintendoUSBHIDReportFormatTests {
  @Test func switchProUSBReportParsesThroughSwitchProParser() throws {
    var state = VirtualGamepadState()
    state.buttons =
      (1 << GamepadHIDDescriptor.ButtonBit.a.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.leftBumper.rawValue)
      | (1 << GamepadHIDDescriptor.ButtonBit.guide.rawValue)
    state.hat = .north
    state.leftStickX = 16_383
    state.leftTrigger = 16_383
    let report = SwitchProUSBHIDReportFormat().buildInputReport(from: state)
    #expect(report.count == SwitchProUSBHIDDescriptor.inputReportLength)
    #expect(report[0] == 0x30)
    #expect(report[2] == SwitchProUSBHIDDescriptor.usbBatteryAndConnection)

    let parser = SwitchProParser()
    var idle = [UInt8](repeating: 0, count: 49)
    idle[0] = 0x30
    _ = try parser.parse(data: Data(idle))
    let events = try parser.parse(data: Data(report))
    #expect(events.contains(.buttonPressed(.a)))
    #expect(events.contains(.buttonPressed(.leftBumper)))
    #expect(events.contains(.buttonPressed(.guide)))
    #expect(events.contains(.buttonPressed(.l2Digital)))
    #expect(events.contains(.dpadChanged(.north)))
  }

  @Test func switchProUSBHandshakeAndSubcommandAck() {
    let format = SwitchProUSBHIDReportFormat()
    let handshake = format.inputReportRespondingToHostOutput([0x80, 0x02])
    #expect(handshake?.count == SwitchProUSBHIDDescriptor.inputReportLength)
    #expect(handshake?.first == 0x81)
    #expect(handshake?[1] == 0x02)

    let stripped = UserSpaceOutputDispatcher.normalizedHostOutputReport(
      reportID: 0x80,
      bytes: [0x02]
    )
    #expect(format.inputReportRespondingToHostOutput(stripped)?.first == 0x81)

    let ack = format.inputReportRespondingToHostOutput(
      [0x01, 0x00] + [UInt8](repeating: 0, count: 8) + [0x03, 0x30]
    )
    #expect(ack?.first == 0x21)
    #expect(ack?[13] == 0x80)
    #expect(ack?[14] == 0x03)
    #expect(format.inputReportRespondingToHostOutput([0x10, 0x00]) == nil)

    let status = format.inputReportRespondingToHostOutput([0x80, 0x01])
    #expect(status?.first == 0x81)
    #expect(status?[1] == 0x01)
    #expect(status?[3] == SwitchProUSBHIDDescriptor.proControllerDeviceType)

    let spi = format.inputReportRespondingToHostOutput(
      [0x01, 0x00] + [UInt8](repeating: 0, count: 8) + [0x10, 0x3D, 0x60, 0x00, 0x00, 0x12]
    )
    #expect(spi?.first == 0x21)
    #expect(spi?[14] == 0x10)
    #expect(spi?[15] == 0x3D)
    #expect(spi?[16] == 0x60)
    #expect(spi?[19] == 0x12)
    #expect(spi?[20] != 0xFF)

    #expect(format.hostGetReport(reportID: 0x81, maxSize: 64)?.first == 0x81)
    #expect(format.hostGetReport(reportID: 0x21, maxSize: 64)?.first == 0x21)
    #expect(format.hostGetReport(reportID: 0x30, maxSize: 64) == nil)
    #expect(format.hostGetReport(reportID: 0x05, maxSize: 8)?.count == 8)
  }

  @Test func switchProIdentityUsesNintendoPresentation() {
    #expect(VirtualDeviceProfile.switchProUSB.presentation == .nintendo)
    #expect(VirtualDeviceProfile.switchProUSB.productName == "Pro Controller")
    #expect(VirtualDeviceProfile.switchProUSB.vendorID == 0x057E)
    #expect(VirtualDeviceProfile.switchProUSB.productID == 0x2009)

    let physical = ApplicationServiceDeviceDescription(
      name: "Switch",
      vendorID: 0x057E,
      productID: 0x2009,
      parser: "SwitchPro",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .switchPro
    )
    #expect(PublishedVirtualIdentity.profile(for: physical, requested: .automatic) == .switchProUSB)
    #expect(
      PublishedVirtualIdentity.profile(for: physical, requested: .switchPro) == .switchProUSB
    )
  }

  @Test func switchProUSBDescriptorDeclaresJoystickReport30() throws {
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: SwitchProUSBHIDDescriptor.descriptor)
    )
    #expect(
      parsed.payloadSizeBytesByReportID[0x30] == SwitchProUSBHIDDescriptor.inputReportLength - 1
    )
    let report30 = parsed.fields.filter { $0.reportID == 0x30 }
    #expect(report30.contains { $0.usagePage == 0x09 && $0.usage == 0x01 })
    #expect(report30.contains { $0.usage == 0x30 || $0.usage == 0x0001_0030 })
    #expect(parsed.payloadSizeBytesByReportID[0x21] == 63)
    #expect(parsed.payloadSizeBytesByReportID[0x81] == 63)
  }
}
