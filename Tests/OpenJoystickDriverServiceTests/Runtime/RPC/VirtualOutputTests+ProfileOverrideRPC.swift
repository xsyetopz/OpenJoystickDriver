import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

/// A server whose automatic dispatcher builds retarget probes and reads overrides from isolated
/// defaults.
extension VirtualOutputTests {
  func profileOverrideServer(
    _ identifiers: [DeviceIdentifier] = [DeviceIdentifier(vendorID: 1, productID: 2)],
    failure: (VirtualHIDProfileID, ProfileRetargetFailure)? = nil,
    outputEnabled: Bool = true,
    activationGate: (VirtualHIDProfileID, InstallationGate)? = nil,
    timeouts: VirtualOutputTransitionTimeouts = .standard,
    configure: (URL) -> Void = { _ in }
  ) async throws -> ProfileOverrideServerFixture {
    let suiteName = "OpenJoystickDriverTests.ProfileOverrideRPC.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let personaDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(suiteName, isDirectory: true)
    configure(personaDirectory)
    let store = VirtualHIDProfileOverrideStore(directory: personaDirectory)
    let log = RetargetEventLog()
    let descriptions = provider(identifiers.map { description($0) })
    let overrideProvider: @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? =
      { store.override(vendorID: $0.vendorID, productID: $0.productID, unit: $0.unitIdentifier) }
    let dispatcher = VirtualOutputRouter()
    let profileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingRouter = RemappingOutputRouter(
      library: profileLibrary,
      engine: RemappingEventEngine(sink: CoreGraphicsSystemInputSink(access: postEventAccess)),
      virtualOutput: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    let server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: remappingRouter),
      permissionManager: PermissionManager(),
      dispatcher: dispatcher,
      remappingProfileLibrary: profileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess,
      userSpaceDispatcherFactory: { _ in
        AutomaticUserSpaceOutputDispatcher(
          deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
          ownershipProvider: { _ in .exclusiveRawUSB },
          builder: { profile in
            let backend = RetargetBackendProbe(
              profile: profile,
              log: log,
              failsActivation: failure.map { $0.0 == profile && $0.1 == .activation } ?? false,
              activationGate: activationGate.flatMap { $0.0 == profile ? $0.1 : nil }
            )
            log.append(backend)
            return backend
          },
          descriptionsProvider: descriptions,
          overrideProvider: overrideProvider
        )
      },
      connectedIdentifierProvider: { identifiers },
      virtualOutputTransitionTimeouts: timeouts,
      defaults: defaults,
      personaDirectory: personaDirectory
    )
    if outputEnabled { _ = await server.activateVirtualOutputBackendForCurrentDevices() }
    return ProfileOverrideServerFixture(
      server: server,
      defaults: defaults,
      personaDirectory: personaDirectory,
      suiteName: suiteName,
      log: log
    )
  }

  @Test
  func settingAnOverridePersistsAndRetargetsTheController() async throws {
    let fixture = try await profileOverrideServer()

    let result = await fixture.change(.set("hid-generic"))

    #expect(
      result
        == VirtualHIDProfileOverrideResult(
          requested: .generic,
          live: .generic,
          source: "override",
          failure: nil
        )
    )
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .generic)
    #expect(fixture.log.built().map(\.profile) == [.xboxOneSBluetooth, .generic])
    await fixture.tearDown()
  }

  @Test
  func resettingAnOverrideReturnsTheControllerToAutomaticSelection() async throws {
    let fixture = try await profileOverrideServer()
    _ = await fixture.change(.set("hid-generic"))

    let result = await fixture.change(.reset)

    #expect(
      result
        == VirtualHIDProfileOverrideResult(
          requested: nil,
          live: .xboxOneSBluetooth,
          source: "automatic",
          failure: nil
        )
    )
    #expect(fixture.store.override(vendorID: 1, productID: 2) == nil)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func anUnknownProfileIsRejectedWithoutPersisting() async throws {
    let fixture = try await profileOverrideServer()

    let result = await fixture.change(.set("xone-hid"))

    #expect(result.failure == .unknownProfile)
    #expect(result.requested == nil)
    #expect(result.live == .xboxOneSBluetooth)
    #expect(fixture.store.files.isEmpty)
    #expect(fixture.log.built().count == 1)
    await fixture.tearDown()
  }

  @Test
  func anUnmatchedControllerIsNotFoundAndNothingIsPersisted() async throws {
    let fixture = try await profileOverrideServer()

    let otherModel = await fixture.change(.set("hid-generic"), vendorID: 3)
    let otherSession = await fixture.change(.set("hid-generic"), runtimeIdentifier: "missing")

    #expect(otherModel.failure == .controllerNotFound)
    #expect(otherSession.failure == .controllerNotFound)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func disabledOutputStillPersistsTheOverride() async throws {
    let fixture = try await profileOverrideServer(outputEnabled: false)

    let result = await fixture.change(.set("hid-generic"))

    #expect(
      result
        == VirtualHIDProfileOverrideResult(
          requested: .generic,
          live: nil,
          source: "override",
          failure: .outputDisabled
        )
    )
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .generic)
    await fixture.tearDown()
  }

  @Test
  func aStoppedServerRejectsOverrideChangesWithoutPersisting() async throws {
    let fixture = try await profileOverrideServer()
    await fixture.server.stop()

    let result = await fixture.change(.set("hid-generic"))

    #expect(result.failure == .serverStopped)
    #expect(result.requested == .generic)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func failedActivationRestoresThePriorStoredOverride() async throws {
    let fixture = try await profileOverrideServer(failure: (.xboxOneSBluetooth, .activation)) {
      VirtualHIDProfileOverrideStore(directory: $0).setGenericForTest()
    }
    #expect(fixture.log.built().map(\.profile) == [.generic])

    let result = await fixture.change(.set("hid-xbox-one-s-bt"))

    guard case .activationFailed(let detail) = result.failure else {
      Issue.record("Expected activation-failed, got \(String(describing: result.failure))")
      return
    }
    #expect(!detail.isEmpty)
    #expect(result.requested == .xboxOneSBluetooth)
    #expect(result.live == .generic)
    #expect(result.source == "override")
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .generic)
    #expect(fixture.log.built().first?.closed == false)
    await fixture.tearDown()
  }

  @Test
  func anOverrideRetargetsEveryControllerOfTheModel() async throws {
    let first = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    let second = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 2)
    let fixture = try await profileOverrideServer([first, second])

    let result = await fixture.change(.set("hid-generic"))
    let unmatched = await fixture.change(.reset, runtimeIdentifier: "missing")

    #expect(result.failure == nil)
    #expect(result.live == .generic)
    let automatic = fixture.server.automaticUserSpaceDispatcher()
    for identifier in [first, second] {
      let state = automatic?.profileState(runtimeIdentifier: identifier.runtimeIdentifier)
      #expect(state?.selection?.profileID == .generic)
    }
    #expect(unmatched.failure == .controllerNotFound)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .generic)
    await fixture.tearDown()
  }

  @Test
  func overrideRequestsRoundTripThroughTheLocalRPCBridge() async throws {
    let fixture = try await profileOverrideServer()
    let set = try await localRPC(
      fixture.server,
      method: "setVirtualHIDProfileOverride",
      arguments: LocalServiceRPCVirtualHIDProfileOverrideArguments(
        vendorID: 1,
        productID: 2,
        profile: "hid-generic"
      )
    )
    let reset = try await localRPC(
      fixture.server,
      method: "resetVirtualHIDProfileOverride",
      arguments: LocalServiceRPCDeviceArguments(vendorID: 1, productID: 2)
    )

    #expect(
      set
        == VirtualHIDProfileOverrideResult(
          requested: .generic,
          live: .generic,
          source: "override",
          failure: nil
        )
    )
    #expect(
      reset
        == VirtualHIDProfileOverrideResult(
          requested: nil,
          live: .xboxOneSBluetooth,
          source: "automatic",
          failure: nil
        )
    )
    await fixture.tearDown()
  }

  private func localRPC(
    _ server: ApplicationServiceServer,
    method: String,
    arguments: some Encodable
  ) async throws -> VirtualHIDProfileOverrideResult {
    let envelope: [String: String] = [
      "method": method, "arguments": try JSONEncoder().encode(arguments).base64EncodedString(),
    ]
    let request = try JSONDecoder().decode(
      LocalServiceRPCRequest.self,
      from: JSONEncoder().encode(envelope)
    )
    let response = await server.handleLocalRPC(request)
    let data = try #require(response.result, "\(String(describing: response.error))")
    return try JSONDecoder().decode(VirtualHIDProfileOverrideResult.self, from: data)
  }

  @Test
  func aTimedOutRetargetRestoresThePriorStoredOverride() async throws {
    let gate = InstallationGate()
    let fixture = try await profileOverrideServer(
      activationGate: (.xboxOneSBluetooth, gate),
      timeouts: VirtualOutputTransitionTimeouts(
        stageNanoseconds: 2_000_000_000,
        perControllerNanoseconds: 50_000_000,
        totalNanoseconds: 10_000_000_000
      )
    ) { VirtualHIDProfileOverrideStore(directory: $0).setGenericForTest() }

    let result = await fixture.change(.set("hid-xbox-one-s-bt"))

    guard case .activationFailed = result.failure else {
      Issue.record("Expected activation-failed, got \(String(describing: result.failure))")
      return
    }
    #expect(result.live == .generic)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .generic)
    await gate.release()
    await fixture.tearDown()
  }
}
