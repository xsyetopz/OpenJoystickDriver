import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct RemappingProfileSwitchBridgeTests {
  private struct Failure: Error {}

  /// Records the profiles that the bridge activates.
  private final class RecordingServer: AutomationService, @unchecked Sendable {
    private let state = Locked<[UUID]>([])
    private let failure: (any Error)?

    init(failure: (any Error)? = nil) { self.failure = failure }

    var activations: [UUID] { state.withLock { $0 } }

    func connectedDevices() async -> [ApplicationServiceDeviceDescription] { [] }

    func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
      throw Failure()
    }

    func activateRemappingProfile(
      id: UUID,
      allowEmpty: Bool
    ) async throws -> ApplicationServiceRemappingSnapshotPayload {
      if let failure { throw failure }
      state.withLock { $0.append(id) }
      return ApplicationServiceRemappingSnapshotPayload(
        profiles: [],
        activeProfiles: [],
        routes: [],
        postEventAccess: .granted
      )
    }

    func deactivateRemappingProfile(
      id: UUID
    ) async throws -> ApplicationServiceRemappingSnapshotPayload { throw Failure() }
  }

  /// A bridge over a library of `First` and `Second` of one model and `Foreign` of another.
  private struct Fixture {
    let bridge: RemappingProfileSwitchBridge
    let server: RecordingServer
    let lines: Locked<[String]>
    let first: RemappingProfile
    let second: RemappingProfile
    let foreign: RemappingProfile
    let identifier = LogicalControllerID(vendorID: 1118, productID: 654, locationID: 1)
  }

  @Test
  func nextActivatesThroughTheServiceAndLogsBothNames() async throws {
    try await withFixture { fixture in
      await fixture.bridge.switchProfile(
        .next,
        from: fixture.first.id,
        for: fixture.identifier
      )
      #expect(fixture.server.activations == [fixture.second.id])
      #expect(fixture.lines.withLock { $0 } == ["[ProfileSwitch] Profile \"First\" -> \"Second\""])
    }
  }

  @Test
  func anActivationFailureIsLogged() async throws {
    try await withFixture(failure: Failure()) { fixture in
      await fixture.bridge.switchProfile(
        .next,
        from: fixture.first.id,
        for: fixture.identifier
      )
      let lines = fixture.lines.withLock { $0 }
      #expect(fixture.server.activations.isEmpty)
      #expect(lines.count == 1)
      #expect(lines.first?.hasPrefix("[ProfileSwitch] Switch from \(fixture.first.id)") == true)
    }
  }

  @Test
  func aTargetOfAnotherModelIsLoggedNotActivated() async throws {
    try await withFixture { fixture in
      await fixture.bridge.switchProfile(
        .profile(fixture.foreign.id),
        from: fixture.first.id,
        for: fixture.identifier
      )
      #expect(fixture.server.activations.isEmpty)
      #expect(fixture.lines.withLock { $0.count } == 1)
    }
  }

  private func profile(_ name: String, product: UInt16 = 654) -> RemappingProfile {
    RemappingProfile(
      id: UUID(),
      name: name,
      device: RemappingDeviceScope(vendorID: 1118, productID: product),
      applicationScope: .global,
      bindings: []
    )
  }

  private func withFixture(
    failure: (any Error)? = nil,
    _ body: (Fixture) async throws -> Void
  ) async throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = RemappingProfileLibrary(directory: directory)
    let first = profile("First")
    let second = profile("Second")
    let foreign = profile("Foreign", product: 9)
    for item in [first, second, foreign] { try await library.create(item) }
    let lines = Locked<[String]>([])
    let bridge = RemappingProfileSwitchBridge(library: library) { line in
      lines.withLock { $0.append(line) }
    }
    let server = RecordingServer(failure: failure)
    bridge.attach(server)
    try await body(
      Fixture(
        bridge: bridge,
        server: server,
        lines: lines,
        first: first,
        second: second,
        foreign: foreign
      )
    )
  }
}
