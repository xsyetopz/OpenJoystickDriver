import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension RemappingRequestCoordinatorTests {
  @Test
  func calibrationRequestsValidateIdentifiersAndReportUnavailableMotion() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    for identifier in ["", String(repeating: "é", count: 257)] {
      let result = await harness.coordinator.motionCalibration(
        .init(runtimeIdentifier: identifier, command: .start)
      )
      guard case .failure(let error) = result else {
        Issue.record("Expected invalid calibration arguments.")
        continue
      }
      #expect(error.code == .invalidArguments)
    }

    let device = remappingRouterDevice(1)
    let absent = await harness.coordinator.motionCalibration(
      .init(runtimeIdentifier: device.runtimeIdentifier)
    )
    guard case .failure(let absentError) = absent else {
      Issue.record("Expected an unavailable controller.")
      return
    }
    #expect(absentError.code == .controllerUnavailable)

    let original = profile(name: "Calibration")
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id, allowEmpty: false).get()
    try await harness.routerHarness.router.dispatchCausally(.activation, from: device)
    let status = try await harness.coordinator.motionCalibration(
      .init(runtimeIdentifier: device.runtimeIdentifier)
    ).get()
    #expect(!status.hasMotionBaseline)
    #expect(!status.isCollecting)
    let start = await harness.coordinator.motionCalibration(
      .init(runtimeIdentifier: device.runtimeIdentifier, command: .start)
    )
    guard case .failure(let startError) = start else {
      Issue.record("Expected unavailable motion before the first sample.")
      return
    }
    #expect(startError.code == .motionUnavailable)
    try await harness.routerHarness.router.shutdown()
  }

  func makeHarness(
    postEventProbe: RPCPostEventProbe = RPCPostEventProbe(preflight: [true], requestResult: true),
    maximumResponseBytes: Int = ApplicationServiceRemappingRPC.maximumPayloadBytes
  ) async throws -> CoordinatorHarness {
    let routerHarness = try await RemappingRouterHarness.make(
      frontmostBundleIdentifier: "com.example.Game",
      accessState: .granted
    )
    let postEventAccess = CoreGraphicsPostEventAccess(probe: postEventProbe)
    return CoordinatorHarness(
      routerHarness: routerHarness,
      coordinator: RemappingRequestCoordinator(
        library: routerHarness.library,
        router: routerHarness.router,
        postEventAccess: postEventAccess,
        maximumResponseBytes: maximumResponseBytes
      )
    )
  }

  func makeRollbackHarness() throws -> TransactionRollbackHarness {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let library = RemappingProfileLibrary(directory: directory)

    let recorder = RemappingRouterRecorder()
    let sink = TransactionFaultSink(recorder: recorder)
    let router = RemappingOutputRouter(
      library: library,
      engine: RemappingEventEngine(sink: sink),
      virtualOutput: RemappingRouterVirtualOutput(recorder: recorder),
      foregroundApplication: RemappingRouterForeground("com.example.Game"),
      postEventAccess: RemappingRouterAccess(.granted),
      tickerIntervalNanoseconds: nil
    ) { 1_000_000_000 }
    let access = CoreGraphicsPostEventAccess(
      probe: RPCPostEventProbe(preflight: [true], requestResult: true)
    )
    return TransactionRollbackHarness(
      directory: directory,
      library: library,
      router: router,
      coordinator: RemappingRequestCoordinator(
        library: library,
        router: router,
        postEventAccess: access
      ),
      sink: sink
    )
  }

  func expectRecoveredEngineFailure(
    _ result: RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>
  ) {
    guard case .failure(let error) = result else {
      Issue.record("Expected a router engine failure.")
      return
    }
    #expect(error.code == .routerEngineUnavailable)
  }

  func profile(
    id: UUID = UUID(),
    name: String,
    vendorID: UInt16 = 1118,
    productID: UInt16 = 654,
    key: RemappingKeyboardKey = .space
  ) -> RemappingProfile {
    RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: key, modifiers: []))
      ]
    )
  }

  func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? Int)
  }
}
