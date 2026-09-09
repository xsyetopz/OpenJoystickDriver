import Testing

@testable import OpenJoystickDriverKit

struct NintendoUSBHostProtocolTests {
  private func subcommand(_ command: UInt8, data: [UInt8] = [], intensity: UInt8 = 0) -> [UInt8] {
    [1, 0] + SwitchProRumbleCodec.encode(intensity: intensity)
      + SwitchProRumbleCodec.encode(intensity: intensity) + [command] + data
  }

  @Test
  func initializationAcknowledgementsAndIdentity() throws {
    let session = VirtualHostProtocolSession(format: SwitchProUSBHIDReportFormat())
    for command: UInt8 in [1, 2, 3] {
      let reply = try #require(session.setReport(virtualHostOutput([0x80, command])).inputReport)
      #expect(reply.count == 64)
      #expect(reply[0...1] == [0x81, command])
    }
    #expect(try session.setReport(virtualHostOutput([0x80, 4])).inputReport == nil)
    let status = try #require(session.setReport(virtualHostOutput([0x80, 1])).inputReport)
    let info = try #require(session.setReport(virtualHostOutput(subcommand(2))).inputReport)
    #expect(info[13...14] == [0x82, 2])
    #expect(status[3] == 3)
    #expect(info[17] == 3)
    #expect(Array(status[4..<10]) == Array(info[19..<25]))
    let mode = try #require(
      session.setReport(virtualHostOutput(subcommand(3, data: [0x30]))).inputReport
    )
    #expect(mode[13...14] == [0x80, 3])
  }

  @Test
  func acknowledgementAndRumbleAreBothReturnedAndSessionsAreIndependent() throws {
    let first = VirtualHostProtocolSession(format: SwitchProUSBHIDReportFormat())
    let second = VirtualHostProtocolSession(format: SwitchProUSBHIDReportFormat())
    let enabled = try first.setReport(
      virtualHostOutput(subcommand(0x48, data: [1], intensity: 255))
    )
    #expect(enabled.inputReport?[14] == 0x48)
    #expect(enabled.rumble == VirtualRumbleCommand(left: 255, right: 255))
    let request = try virtualHostOutput(subcommand(0x30, data: [1], intensity: 255))
    #expect(try first.setReport(request).rumble?.left == 255)
    #expect(try second.setReport(request).rumble?.left == 0)
    let disabled = try first.setReport(
      virtualHostOutput(subcommand(0x48, data: [0], intensity: 255))
    )
    #expect(disabled.rumble == VirtualRumbleCommand(left: 0, right: 0))
  }

  @Test
  func spiCalibrationRangesAndResponseBounds() throws {
    let session = VirtualHostProtocolSession(format: SwitchProUSBHIDReportFormat())
    for (offset, length): (UInt16, UInt8) in [
      (0x603D, 18), (0x6020, 24), (0x8010, 22), (0x8026, 20),
    ] {
      let data = [UInt8(truncatingIfNeeded: offset), UInt8(offset >> 8), 0, 0, length]
      let reply = try #require(
        session.setReport(virtualHostOutput(subcommand(0x10, data: data))).inputReport
      )
      #expect(reply.count == 64)
      #expect(reply[13] == 0x90)
      #expect(Array(reply[15..<20]) == data)
      if offset >= 0x8000 { #expect(reply[20..<(20 + Int(length))].allSatisfy { $0 == 0xFF }) }
    }
    #expect(throws: VirtualHostReportError.malformed) {
      try session.setReport(virtualHostOutput(subcommand(0x10, data: [0x3D, 0x60, 0, 0, 30])))
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try session.setReport(virtualHostOutput(subcommand(0x10, data: [0, 0x90, 0, 0, 18])))
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try session.getReport(type: .feature, reportID: 5, maxSize: 8, currentInput: [])
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try session.getReport(type: .input, reportID: 0x81, maxSize: 64, currentInput: [])
    }
  }

  @Test
  func malformedRequestsDoNotChangeVibrationState() throws {
    let session = VirtualHostProtocolSession(format: SwitchProUSBHIDReportFormat())
    var malformed = subcommand(0x48, data: [1])
    malformed[3] = 0xFE
    #expect(throws: VirtualHostReportError.malformed) {
      try session.setReport(virtualHostOutput(malformed))
    }
    #expect(
      try session.setReport(virtualHostOutput(subcommand(2, intensity: 255))).rumble?.left == 0
    )
    #expect(throws: VirtualHostReportError.malformed) {
      try session.setReport(virtualHostOutput([0x10, 0]))
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try session.setReport(virtualHostOutput(subcommand(0xFF)))
    }
  }

  @Test(arguments: UInt8(0)...UInt8(255))
  func rumbleAmplitudeRoundTrip(intensity: UInt8) throws {
    let encoded = SwitchProRumbleCodec.encode(intensity: intensity)
    let decoded = try #require(SwitchProRumbleCodec.decodeIntensity(encoded[...]))
    #expect(abs(Int(decoded) - Int(intensity)) <= 6)
  }
}
