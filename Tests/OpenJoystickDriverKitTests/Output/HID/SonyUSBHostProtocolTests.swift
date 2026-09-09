import Testing

@testable import OpenJoystickDriverKit

struct SonyUSBHostProtocolTests {
  @Test(arguments: [false, true])
  func serialAndCalibrationAreSessionLocalAndBounded(dualSense: Bool) throws {
    let format: any VirtualGamepadReportFormat =
      dualSense ? DualSenseUSBHIDReportFormat() : DualShock4USBHIDReportFormat()
    let first = VirtualHostProtocolSession(format: format)
    let second = VirtualHostProtocolSession(format: format)
    let serialID: UInt32 = dualSense ? 9 : 0x12
    let serial = try first.getReport(
      type: .feature,
      reportID: serialID,
      maxSize: 64,
      currentInput: []
    )
    #expect(serial.count == (dualSense ? 20 : 16))
    #expect(
      try first.getReport(type: .feature, reportID: serialID, maxSize: 64, currentInput: [])
        == serial
    )
    #expect(
      try second.getReport(type: .feature, reportID: serialID, maxSize: 64, currentInput: [])
        != serial
    )
    #expect(
      try first.getReport(type: .feature, reportID: serialID, maxSize: 4, currentInput: [])
        == Array(serial.prefix(4))
    )
    let calibration = try first.getReport(
      type: .feature,
      reportID: dualSense ? 5 : 2,
      maxSize: 64,
      currentInput: []
    )
    #expect(calibration.count == (dualSense ? 41 : 37))
    for offset in [7, 11, 15, 23, 27, 31] {
      #expect(
        Array(calibration[offset..<(offset + 2)]) != Array(calibration[(offset + 2)..<(offset + 4)])
      )
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try first.getReport(type: .output, reportID: serialID, maxSize: 64, currentInput: [])
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try first.getReport(type: .feature, reportID: 0xFE, maxSize: 64, currentInput: [])
    }
  }

  @Test
  func dualShock4RumbleRequiresItsValidityFlag() throws {
    let session = VirtualHostProtocolSession(format: DualShock4USBHIDReportFormat())
    var bytes = [UInt8](repeating: 0, count: 32)
    bytes[0] = 5
    bytes[4] = 63
    bytes[5] = 127
    #expect(try session.setReport(virtualHostOutput(bytes)).rumble == nil)
    bytes[1] = 1
    #expect(
      try session.setReport(virtualHostOutput(bytes)).rumble
        == VirtualRumbleCommand(left: 127, right: 63)
    )
    bytes[4] = 0
    bytes[5] = 0
    #expect(
      try session.setReport(virtualHostOutput(bytes)).rumble
        == VirtualRumbleCommand(left: 0, right: 0)
    )
    bytes.removeLast()
    #expect(throws: VirtualHostReportError.malformed) {
      try session.setReport(virtualHostOutput(bytes))
    }
  }

  @Test
  func dualSenseSupportsBothRumbleFlagsAndStop() throws {
    let session = VirtualHostProtocolSession(format: DualSenseUSBHIDReportFormat())
    var bytes = [UInt8](repeating: 0, count: 48)
    bytes[0] = 2
    bytes[1] = 3
    bytes[3] = 63
    bytes[4] = 127
    let command = VirtualRumbleCommand(left: 127, right: 63)
    #expect(try session.setReport(virtualHostOutput(bytes)).rumble == command)
    bytes[1] = 2
    bytes[39] = 4
    #expect(try session.setReport(virtualHostOutput(bytes)).rumble == command)
    bytes[1] = 0
    bytes[39] = 0
    #expect(
      try session.setReport(virtualHostOutput(bytes)).rumble
        == VirtualRumbleCommand(left: 0, right: 0)
    )
    let firmware = try session.getReport(
      type: .feature,
      reportID: 0x20,
      maxSize: 64,
      currentInput: []
    )
    #expect(firmware[44...45] == [0x24, 0x02])
    bytes.append(0)
    #expect(throws: VirtualHostReportError.tooLarge) {
      try session.setReport(virtualHostOutput(bytes))
    }
  }
}
