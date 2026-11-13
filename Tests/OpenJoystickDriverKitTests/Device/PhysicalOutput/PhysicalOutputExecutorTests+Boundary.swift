import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Mapped physical output reaching the device manager through its `OutputSink` conformance.
extension PhysicalOutputExecutorTests {
  /// A release through the sink drops the remapping claim and writes the released channel.
  @Test
  func releaseThroughSinkReleasesMappingClaims() async throws {
    let started = try await startSixaxis(locationID: 540)
    let manager = started.manager
    let claim = MappingOutputClaim(
      .rumble(motor: .lowFrequency, intensity: 0.5),
      active: true,
      owner: UUID()
    )
    try await manager.consume(claim, for: started.identifier)
    let before = await started.backend.recordedOutputReports().count

    try await manager.consume(MappingOutputRelease(), for: started.identifier)

    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0]])
    await manager.stop()
  }

  /// A profile color, and its removal, are accepted through the sink for a connected controller.
  @Test
  func profileColorThroughSinkIsAcceptedForConnectedController() async throws {
    let started = try await startSixaxis(locationID: 541)
    let manager = started.manager
    let color = ControllerColor(red: 0, green: 128, blue: 255)
    try await manager.consume(ProfileColorClaim(color), for: started.identifier)
    try await manager.consume(ProfileColorClaim(nil), for: started.identifier)
    await manager.stop()
  }

  /// A release whose channel write fails is refused through the sink.
  @Test
  func releaseThroughSinkIsRefusedWhenWriteFails() async throws {
    let started = try await startSixaxis(locationID: 542)
    let manager = started.manager
    let claim = MappingOutputClaim(
      .rumble(motor: .lowFrequency, intensity: 0.5),
      active: true,
      owner: UUID()
    )
    try await manager.consume(claim, for: started.identifier)
    await started.backend.disableOutputReports()

    await #expect(
      throws: StreamBoundaryError.rejected(.physicalOutput, "mapping outputs not released")
    ) {
      try await manager.consume(MappingOutputRelease(), for: started.identifier)
    }
    await manager.stop()
  }

  /// A profile color whose lightbar write fails is refused through the sink.
  @Test
  func profileColorThroughSinkIsRefusedWhenWriteFails() async throws {
    let started = try await startSixaxis(locationID: 543, productID: 0x05C4)
    let manager = started.manager
    await started.backend.disableOutputReports()

    await #expect(
      throws: StreamBoundaryError.rejected(.physicalOutput, "profile colour not applied")
    ) {
      try await manager.consume(
        ProfileColorClaim(ControllerColor(red: 0, green: 128, blue: 255)),
        for: started.identifier
      )
    }
    await manager.stop()
  }
}
