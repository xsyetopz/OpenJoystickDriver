import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension DriverLifecycleCharacterizationTests {
  /// A `HIDReportLayout` record's startup writes go out through the manager, and a refused write
  /// shows as a failed startup.
  @Test(arguments: [true, false])
  func reportLayoutRecordSendsItsStartupWrites(acceptsOutputReports: Bool) async throws {
    let subject = Subject(
      model: Self.model(0x37D7, 0x2401),
      host: .usb,
      protocolID: .hidReportLayout,
      variant: nil
    )
    let recording = await startHIDController(
      subject,
      transport: "USB",
      locationID: 208,
      acceptsOutputReports: acceptsOutputReports
    )
    let neutral = Data([0x5A, 0xA5, 0xEF] + [UInt8](repeating: 0, count: 29))
    await deliver([neutral], to: recording, locationID: 208)
    let identifier = try #require(await recording.manager.pipelines.keys.first)
    let pipeline = try #require(await recording.manager.pipelines[identifier])
    let status = await pipeline.startupCommandStatus()
    let sent = await recording.backend.recordedOutputReports()
    await recording.manager.stop()
    #expect(status == (acceptsOutputReports ? "succeeded" : "failed"))
    if acceptsOutputReports {
      #expect(sent.map(\.reportID) == [3, 3, 3, 3])
      #expect(sent.last.map { Array($0.bytes[1...4]) } == [0x5A, 0xA5, 0x11, 0x07])
    }
  }
}
