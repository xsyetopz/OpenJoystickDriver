import Testing

@testable import OpenJoystickDriverKit

struct VirtualMotionReportTests {
  private let state = VirtualGamepadState(
    motion: RemappingVirtualMotionState(
      gyroscopeDegreesPerSecond: ControllerMotionVector(x: 10, y: -20, z: 30),
      accelerationG: ControllerMotionVector(x: 0.25, y: 1, z: -0.5),
      deltaNanoseconds: 10_000_000
    ),
    motionTimestampNanoseconds: 10_000_000
  )

  @Test
  func sonyReportsCarryNominalMotionAndMonotonicCounters() {
    let dualShock = DualShock4USBHIDReportFormat().buildInputReport(from: state)
    #expect(signed16(dualShock, at: 13) == 160)
    #expect(signed16(dualShock, at: 15) == -320)
    #expect(signed16(dualShock, at: 17) == 480)
    #expect(signed16(dualShock, at: 19) == 2048)
    #expect(signed16(dualShock, at: 21) == 8192)
    #expect(signed16(dualShock, at: 23) == -4096)
    #expect(unsigned16(dualShock, at: 10) == 1875)

    let dualSense = DualSenseUSBHIDReportFormat().buildInputReport(from: state)
    #expect(Array(dualSense[16..<28]) == Array(dualShock[13..<25]))
    #expect(unsigned32(dualSense, at: 28) == 30_000)
  }

  @Test
  func switchReportUsesProControllerFrameAndAllThreeSamples() {
    let report = SwitchProUSBHIDReportFormat().buildInputReport(from: state)
    #expect(report[1] == 2)
    let first = Array(report[13..<25])
    #expect(signed16(first, at: 0) == 2048)
    #expect(signed16(first, at: 2) == -1024)
    #expect(signed16(first, at: 4) == 4096)
    #expect(signed16(first, at: 6) == -429)
    #expect(signed16(first, at: 8) == -143)
    #expect(signed16(first, at: 10) == -286)
    #expect(Array(report[25..<37]) == first)
    #expect(Array(report[37..<49]) == first)
  }

  @Test
  func onlyFirstPartyMotionFormatsAdvertiseSupport() throws {
    #expect(DualShock4USBHIDReportFormat().supportsMotion)
    #expect(DualSenseUSBHIDReportFormat().supportsMotion)
    #expect(SwitchProUSBHIDReportFormat().supportsMotion)
    #expect(!OJDGenericGamepadFormat().supportsMotion)
    #expect(!OJDSDLGamepadFormat().supportsMotion)
    #expect(!Xbox360MacHIDReportFormat().supportsMotion)
  }

  @Test
  func controlUpdatesPreserveMotionAndNeutralizationPreservesTheClock() throws {
    let reports = UserSpaceInputReportState(format: DualSenseUSBHIDReportFormat())
    let motionReport = try #require(reports.updateMotion(state.motion))
    let controlReport = reports.update { $0.buttons = 1 }
    #expect(Array(controlReport[16..<32]) == Array(motionReport[16..<32]))
    let neutral = try #require(reports.updateMotion(nil))
    #expect(neutral[16..<28].allSatisfy { $0 == 0 })
    #expect(Array(neutral[28..<32]) == Array(motionReport[28..<32]))
  }

  @Test
  func switchOutputCoalescesExactlyThreeOrderedSamples() throws {
    let reports = UserSpaceInputReportState(format: SwitchProUSBHIDReportFormat())
    let samples = [10.0, 20.0, 30.0].map { value in
      RemappingVirtualMotionState(
        gyroscopeDegreesPerSecond: ControllerMotionVector(x: value, y: 0, z: 0),
        accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
        deltaNanoseconds: 5_000_000
      )
    }
    #expect(reports.updateMotion(samples[0]) == nil)
    #expect(reports.updateMotion(samples[1]) == nil)
    let report = try #require(reports.updateMotion(samples[2]))
    #expect(report[1] == 3)
    #expect(signed16(report, at: 21) == -143)
    #expect(signed16(report, at: 33) == -286)
    #expect(signed16(report, at: 45) == -429)
  }

  private func unsigned16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
  }

  private func signed16(_ bytes: [UInt8], at offset: Int) -> Int16 {
    Int16(bitPattern: unsigned16(bytes, at: offset))
  }

  private func unsigned32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }
}
