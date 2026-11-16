import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Command 18 (grip rumble) of the pinned openflydigi sources as a rumble template.
///
/// The template is a `HIDReportLayout` record's: report ID 3, 32 bytes, `5A A5 12 06`, four motor
/// bytes and no checksum byte. The frame is source-derived; no pad has received it.
struct FlydigiGripRumbleTests {
  private static let record: Data = {
    let report = ([0x03, 0x5A, 0xA5, 0x12, 0x06] + [UInt8](repeating: 0, count: 27))
      .map { unsafe String(format: "%02X", $0) }.joined(separator: " ")
    return PropertyListFixture.bytes(
      json: """
        {"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Controller",
          "vendorID": 14295, "productID": 9217,
        "modes": [{"id": "default", "protocol": {"family": "HIDReportLayout"},
          "session": {"rumble": {"report": {"kind": "Output", "id": 3, "length": 32},
            "bytes": "\(report)",
            "lowFrequency": {"byte": 5}, "highFrequency": {"byte": 6},
            "leftTrigger": {"byte": 7}, "rightTrigger": {"byte": 8}}}}],
        "input": {"layouts": [{"report": {"id": 1, "length": {"exactly": 15}},
          "buttons": [{"control": "South", "bitOffset": 76, "bitSize": 1}]}]}}
        """
    )
  }()

  private static func driver() throws -> any PhysicalProtocolDriver {
    let decoded = try ControllerRecordSet.decode(
      ControllerRecordSet.ordered(record, file: "record")
    )
    let profile = try DeviceCatalog.makeRuntimeProfile(decoded.document)
    let result = ProtocolDriverRegistry.makeUnobservedDriver(
      protocolID: profile.physicalProtocolID,
      variant: profile.physicalProtocolVariant,
      record: profile,
      model: decoded.model,
      transportProfile: profile.transportProfile
    )
    return try result.get()
  }

  private static func report(of writes: [PhysicalOutputWrite]) throws -> PhysicalHIDOutputReport {
    let write = try #require(writes.count == 1 ? writes.first : nil)
    guard case .hidOutput(let report) = write else { throw ReportError.notHID }
    return report
  }

  private enum ReportError: Error { case notHID }

  @Test
  func gripAndTriggerLevelsFillFourMotorBytesOfOneFrame() throws {
    let intensities = RumbleIntensities(
      lowFrequency: UnipolarValue(0x8080),
      highFrequency: UnipolarValue(0x4040),
      leftTrigger: UnipolarValue(0xFFFF),
      rightTrigger: UnipolarValue(0x0101)
    )
    let report = try Self.report(
      of: try Self.driver().encode(.setRumble(intensities, duration: .held)).writes
    )
    #expect(report.reportID == 0x03)
    #expect(report.bytes.count == 32)
    #expect(Array(report.bytes[0..<9]) == [0x03, 0x5A, 0xA5, 0x12, 0x06, 0x80, 0x40, 0xFF, 0x01])
    #expect(report.bytes[9...].allSatisfy { $0 == 0 })
  }

  @Test
  func commandLineLevelsLeft128AndRight64SendOneFrame() throws {
    let intensities = RumbleIntensities(
      lowFrequency: UnipolarValue(byte: 128),
      highFrequency: UnipolarValue(byte: 64)
    )
    let report = try Self.report(
      of: try Self.driver().encode(.setRumble(intensities, duration: .held)).writes
    )
    #expect(Array(report.bytes[0..<9]) == [0x03, 0x5A, 0xA5, 0x12, 0x06, 0x80, 0x40, 0, 0])
  }

  @Test
  func stopRumbleZeroesMotorBytesAndKeepsEnvelope() throws {
    let report = try Self.report(of: try Self.driver().encode(.stopRumble).writes)
    #expect(Array(report.bytes[0..<9]) == [0x03, 0x5A, 0xA5, 0x12, 0x06, 0, 0, 0, 0])
  }
}
