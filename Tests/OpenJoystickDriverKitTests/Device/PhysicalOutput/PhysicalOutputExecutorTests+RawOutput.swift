import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Raw bytes written to a connected controller through the output queue.
extension PhysicalOutputExecutorTests {
  /// An output report reaches the HID device with the bytes and report ID given.
  @Test
  func rawHIDOutputWritesTheReport() async throws {
    let started = try await startSixaxis(locationID: 560)
    let manager = started.manager
    let before = await started.backend.recordedOutputReports().count

    let result = await manager.sendRawOutput(
      ControllerRawOutput(destination: .hidOutput, reportID: 0x51, bytes: [0x51, 0x00, 0xC8]),
      for: .model(started.identifier.model)
    )

    #expect(result.outcome == .delivered)
    let written = await started.backend.recordedOutputReports().dropFirst(before)
    #expect(
      Array(written) == [PhysicalHIDOutputReport(reportID: 0x51, bytes: [0x51, 0x00, 0xC8])]
    )
    await manager.stop()
  }

  /// A feature report goes to the feature path, not the output path.
  @Test
  func rawHIDFeatureWritesAFeatureReport() async throws {
    let started = try await startSixaxis(locationID: 561)
    let manager = started.manager
    let outputsBefore = await started.backend.recordedOutputReports().count
    let featuresBefore = await started.backend.recordedFeatureReports().count

    let result = await manager.sendRawOutput(
      ControllerRawOutput(destination: .hidFeature, bytes: [0xFA, 0xFE]),
      for: .model(started.identifier.model)
    )

    #expect(result.outcome == .delivered)
    #expect(await started.backend.recordedOutputReports().count == outputsBefore)
    let features = await started.backend.recordedFeatureReports().dropFirst(featuresBefore)
    #expect(Array(features) == [PhysicalHIDOutputReport(reportID: 0, bytes: [0xFA, 0xFE])])
    await manager.stop()
  }

  /// A malformed write is refused before it reaches the device.
  @Test
  func rawOutputThatIsNotValidIsRefusedWithoutWriting() async throws {
    let started = try await startSixaxis(locationID: 562)
    let manager = started.manager
    let before = await started.backend.recordedOutputReports().count

    let result = await manager.sendRawOutput(
      ControllerRawOutput(destination: .hidOutput, reportID: 0x51, bytes: [0x52]),
      for: .model(started.identifier.model)
    )

    #expect(result.outcome == .invalidValue)
    #expect(await started.backend.recordedOutputReports().count == before)
    await manager.stop()
  }

  /// A controller that is not connected reports not found.
  @Test
  func rawOutputToUnknownControllerIsNotFound() async throws {
    let started = try await startSixaxis(locationID: 563)
    let manager = started.manager

    let result = await manager.sendRawOutput(
      ControllerRawOutput(destination: .hidOutput, bytes: [0x01]),
      for: .model(ControllerModelID(vendorID: 0x1234, productID: 0x5678))
    )

    #expect(result.outcome == .notFound)
    await manager.stop()
  }
}

/// The validity rules and text forms of a raw write.
struct ControllerRawOutputTests {
  @Test
  func hexParsingAcceptsEitherCaseAndAnySpacing() {
    #expect(ControllerRawOutput.parseHex("51 00 ff") == [0x51, 0x00, 0xFF])
    #expect(ControllerRawOutput.parseHex(" 0a  0B ") == [0x0A, 0x0B])
  }

  @Test(arguments: ["", " ", "5", "510", "GG", "0x51", "51,00"])
  func hexParsingRefusesAnythingElse(_ text: String) {
    #expect(ControllerRawOutput.parseHex(text) == nil)
  }

  @Test
  func lengthIsOneThroughSixtyFour() {
    #expect(!ControllerRawOutput(destination: .hidOutput, bytes: []).isValid)
    let full = [UInt8](repeating: 1, count: ControllerRawOutput.maxByteCount)
    #expect(ControllerRawOutput(destination: .hidOutput, bytes: full).isValid)
    #expect(!ControllerRawOutput(destination: .hidOutput, bytes: full + [1]).isValid)
  }

  @Test
  func nonzeroReportIDMustLeadTheBytes() {
    #expect(ControllerRawOutput(destination: .hidOutput, reportID: 5, bytes: [5, 1]).isValid)
    #expect(!ControllerRawOutput(destination: .hidOutput, reportID: 5, bytes: [1, 5]).isValid)
    #expect(ControllerRawOutput(destination: .hidFeature, reportID: 0, bytes: [5]).isValid)
  }

  @Test
  func usbNeedsAnEndpointAndNoReportID() {
    #expect(ControllerRawOutput(destination: .usbInterrupt, endpoint: 2, bytes: [1]).isValid)
    #expect(!ControllerRawOutput(destination: .usbInterrupt, bytes: [1]).isValid)
    #expect(
      !ControllerRawOutput(destination: .usbInterrupt, reportID: 1, endpoint: 2, bytes: [1]).isValid
    )
    #expect(!ControllerRawOutput(destination: .hidOutput, endpoint: 2, bytes: [1]).isValid)
  }

  @Test
  func hexPrintsUppercasePairs() {
    #expect(ControllerRawOutput(destination: .hidOutput, bytes: [0x0A, 0xFF, 0]).hex == "0A FF 00")
  }

  @Test
  func usbWritePlansOnePacketToTheEndpoint() {
    let output = ControllerRawOutput(destination: .usbInterrupt, endpoint: 3, bytes: [9, 8])
    #expect(
      output.write
        == .usb(PhysicalUSBOutputPacket(endpoint: 3, bytes: [9, 8], timeoutMilliseconds: 1_000))
    )
  }
}
