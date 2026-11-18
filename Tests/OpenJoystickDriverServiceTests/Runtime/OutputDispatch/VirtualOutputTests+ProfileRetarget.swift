import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  private struct BuildFailure: Error {}

  private func retargetDispatcher(
    _ identifiers: [LogicalControllerID],
    overrides: ProfileOverrideBox,
    log: RetargetEventLog,
    failure: (VirtualHIDProfileID, ProfileRetargetFailure)? = nil,
    gate: (VirtualHIDProfileID, InstallationGate)? = nil
  ) -> AutomaticUserSpaceOutputDispatcher {
    let overrideProvider: @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? =
      { overrides.profile(for: $0) }
    return AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(
        dispatcher: LoggingOutputDispatcher(),
        installationKey: testPortKeyInstallationKey
      ),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { profile in
        if let failure, failure.0 == profile, failure.1 == .build { throw BuildFailure() }
        let backend = RetargetBackendProbe(
          profile: profile,
          log: log,
          failsActivation: failure.map { $0.0 == profile && $0.1 == .activation } ?? false,
          activationGate: gate.flatMap { $0.0 == profile ? $0.1 : nil }
        )
        log.append(backend)
        return backend
      },
      descriptionsProvider: provider(identifiers),
      overrideProvider: overrideProvider
    )
  }

  @Test
  func profileOverrideChangesBuiltProfile() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    overrides.set(.generic, vendorID: 1)
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)

    try await dispatcher.activate(for: [id])

    #expect(log.built().map(\.profile) == [.generic])
    #expect(dispatcher.selectionSource(for: id) == .override)
    #expect(dispatcher.status.wireValue.contains("targets: Generic"))
    await dispatcher.close()
  }

  @Test
  func retargetRebuildsOnlyTargetController() async throws {
    let first = LogicalControllerID(vendorID: 1, productID: 2)
    let second = LogicalControllerID(vendorID: 3, productID: 4)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([first, second], overrides: overrides, log: log)
    try await dispatcher.activate(for: [first, second])
    #expect(dispatcher.selectionSource(for: first) == .automatic)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: first)

    let built = log.built()
    #expect(built.map(\.profile) == [.sdlCompatible, .sdlCompatible, .generic])
    #expect(built.map(\.closed) == [true, false, false])
    #expect(dispatcher.selectionSource(for: first) == .override)
    #expect(dispatcher.selectionSource(for: second) == .automatic)
    #expect(dispatcher.status.wireValue.contains("targets: Generic; SDLCompatible"))
    await dispatcher.close()
  }

  @Test
  func retargetActivatesReplacementThenNeutralizesBeforeRetiring() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)

    #expect(
      log.snapshot() == [
        "SDLCompatible activate [1]", "Generic activate [1]", "SDLCompatible neutral",
        "SDLCompatible close",
      ]
    )
    await dispatcher.close()
  }

  @Test(arguments: [ProfileRetargetFailure.build, .activation])
  func failedRetargetKeepsPriorBackend(failure: ProfileRetargetFailure) async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher(
      [id],
      overrides: overrides,
      log: log,
      failure: (.generic, failure)
    )
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    await #expect(throws: (any Error).self) { try await dispatcher.retarget(controller: id) }

    let built = log.built()
    #expect(built.first?.profile == .sdlCompatible)
    #expect(built.first?.closed == false)
    #expect(built.dropFirst().allSatisfy { $0.closed })
    #expect(!log.snapshot().contains("SDLCompatible neutral"))
    #expect(dispatcher.status.wireValue.contains("targets: SDLCompatible"))
    #expect(dispatcher.selectionSource(for: id) == .automatic)

    // Later reports keep publishing through the prior backend instead of retrying the override.
    await dispatcher.activateOutput(for: id)
    await dispatcher.activateOutput(for: id)
    #expect(log.built().count == built.count)
    #expect(log.built().first?.closed == false)
    await dispatcher.close()
  }

  @Test
  func dispatchAfterOverrideChangeKeepsBackendUntilRetarget() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    await dispatcher.activateOutput(for: id)
    try await dispatcher.activate(controller: id)

    #expect(log.built().map(\.profile) == [.sdlCompatible])
    #expect(log.built().first?.closed == false)
    #expect(dispatcher.selectionSource(for: id) == .automatic)

    try await dispatcher.retarget(controller: id)

    #expect(log.built().map(\.profile) == [.sdlCompatible, .generic])
    #expect(log.snapshot().contains("SDLCompatible neutral"))
    await dispatcher.close()
  }

  @Test
  func retargetCarriesRemappingSuppressionToReplacement() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])
    await dispatcher.setRemappingOutputSuppressed(true)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)

    #expect(log.built().last?.profile == .generic)
    #expect(log.built().last?.remappingSuppressed == true)
    await dispatcher.close()
  }

  @Test
  func retargetWhileSuppressedPublishesNewProfileOnResume() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])
    await dispatcher.setOutputSuppressed(true)
    #expect(log.built().first?.closed == true)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)
    #expect(log.built().count == 1)
    #expect(dispatcher.selectionSource(for: id) == .override)

    await dispatcher.setOutputSuppressed(false)

    #expect(log.built().map(\.profile) == [.sdlCompatible, .generic])
    #expect(log.built().last?.suppressOutput == false)
    await dispatcher.activateOutput(for: id)
    #expect(log.built().count == 2)
    #expect(dispatcher.status.wireValue.contains("targets: Generic"))
    await dispatcher.close()
  }

  @Test
  func retargetOfStoppedControllerBuildsNothingAndNextSessionUsesOverride() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])
    await dispatcher.controllerDidStop(id)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)
    #expect(log.built().count == 1)

    try await dispatcher.activate(controller: id)

    #expect(log.built().map(\.profile) == [.sdlCompatible, .generic])
    await dispatcher.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func stoppingDuringInFlightRetargetKeepsNoSelectionOrBackend() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let gate = InstallationGate()
    let dispatcher = retargetDispatcher(
      [id],
      overrides: overrides,
      log: log,
      gate: (.generic, gate)
    )
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    let retarget = Task { try await dispatcher.retarget(controller: id) }
    await gate.waitForEntry()
    let stop = Task { await dispatcher.controllerDidStop(id) }
    await gate.waitForCancellation()
    await gate.release()
    await stop.value

    await #expect(throws: (any Error).self) { try await retarget.value }
    #expect(log.built().map(\.profile) == [.sdlCompatible, .generic])
    #expect(log.built().allSatisfy { $0.closed })
    #expect(dispatcher.selectionSource(for: id) == nil)
    #expect(!dispatcher.status.wireValue.contains("targets"))
    await dispatcher.close()
  }

  @Test
  func retargetWithUnchangedProfileIsNoOp() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])

    overrides.set(.sdlCompatible, vendorID: 1)
    try await dispatcher.retarget(controller: id)

    #expect(log.snapshot() == ["SDLCompatible activate [1]"])
    #expect(dispatcher.selectionSource(for: id) == .override)
    await dispatcher.close()
  }

  /// The automatic persona is `SDLCompatible`; opting in to `Generic` switches the live backend
  /// without the controller being unplugged or replugged.
  @Test
  func automaticPersonaIsSDLCompatibleAndOptInSwitchesToGenericWithoutReplug() async throws {
    let id = LogicalControllerID(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])
    #expect(log.built().map(\.profile) == [VirtualHIDProfileID.sdlCompatible])
    #expect(dispatcher.selectionSource(for: id) == .automatic)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)

    #expect(log.built().map(\.profile) == [.sdlCompatible, .generic])
    #expect(dispatcher.selectionSource(for: id) == .override)
    await dispatcher.close()
  }
}
