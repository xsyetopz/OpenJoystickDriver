import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct RuntimeFacadeTests {
  @Test func unresolvedPermissionStatesNeedUserAction() {
    #expect(RuntimePresentation.permissionLabel(.unknown) == "Needs attention")
    #expect(RuntimePresentation.permissionLabel(.denied) == "Needs attention")
  }

  @Test func translatesStatusAndUsesOpaqueDeviceSelector() async throws {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-7"
    )
    let input = DeviceInputState(vendorID: device.vendorID, productID: device.productID)
    let gateway = RuntimeFacadeGatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      inputState: input
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()
    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.readiness == .ready)
    #expect(status.deviceCountLabel == "1 controller connected")
    #expect(status.compatibilityLabel == "SDL2/3")
    #expect(RuntimePresentation.sourceLabel(.button(.south)) == "A / Cross")
    #expect(
      RuntimePresentation.destinationLabel(.keyboard(key: .a, modifiers: [.command, .shift]))
        == "Command + Shift + A"
    )

    let selector = RuntimeDeviceSelector(device: device)
    await viewModel.readInputState(for: selector)
    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .received(let capturedSelector, let capturedState) = captureState else {
      Issue.record("Expected a captured input state")
      return
    }
    #expect(capturedSelector == selector)
    #expect(capturedState == input)
    #expect(await gateway.lastInputSelector == selector)
  }

  @Test func statusReadinessWaitsForPostEventAccess() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-8"
    )
    let profile = makeProfile(name: "Mapped")
    let activeProfile = ApplicationServiceRemappingActiveProfilePayload(
      vendorID: profile.device.vendorID,
      productID: profile.device.productID,
      profileID: profile.id,
      profileName: profile.name,
      applicationScope: profile.applicationScope
    )
    let gateway = RuntimeFacadeGatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      snapshotPayload: snapshot(
        profiles: [profile],
        activeProfiles: [activeProfile],
        postEventAccess: .notAuthorized
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == true)
    #expect(status.postEventAccessLabel == "Needs attention")
    #expect(status.readiness == .needsAttention)
  }

  @Test func statusReadinessIgnoresPostEventAccessWithoutActiveMappings() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-9"
    )
    let gateway = RuntimeFacadeGatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      snapshotPayload: snapshot(profiles: [], postEventAccess: .notAuthorized)
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == false)
    #expect(status.readiness == .ready)
  }

  @Test func statusReadinessRemainsUnknownBeforeRemappingSnapshot() {
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    )
    let presentation = RuntimeStatusPresentation(payload: payload, postEventAccess: .granted)

    #expect(presentation.requiresPostEventAccess == nil)
    #expect(presentation.readiness == .needsAttention)
  }

  @Test func listensUntilItFindsAControllerControl() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    let released = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    var pressed = released
    pressed.pressedButtons = ["A"]
    let gateway = RuntimeFacadeGatewayStub(inputSequence: [released, pressed])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(let capturedSelector, let capturedState, let detectedSource) = captureState
    else {
      Issue.record("Expected the next meaningful controller transition")
      return
    }
    #expect(capturedSelector == selector)
    #expect(detectedSource == .button(.south))
    #expect(RuntimePresentation.detectedSource(from: capturedState) == .button(.south))
  }

  @Test func listenIgnoresAControlHeldBeforeListening() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    var held = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    held.pressedButtons = ["A"]
    let released = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    var pressedAgain = released
    pressedAgain.pressedButtons = ["A"]
    let gateway = RuntimeFacadeGatewayStub(inputSequence: [held, held, released, pressedAgain])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(_, let state, let detectedSource) = captureState else {
      Issue.record("Expected a later press after the held baseline")
      return
    }
    #expect(detectedSource == .button(.south))
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.south))
  }

  @Test func listenPublishesTheTransitionSourceWhenAnotherControlWasAlreadyHeld() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    var baseline = DeviceInputState(vendorID: selector.vendorID, productID: selector.productID)
    baseline.pressedButtons = ["A"]
    var changed = baseline
    changed.pressedButtons = ["A", "B"]
    let gateway = RuntimeFacadeGatewayStub(inputSequence: [baseline, changed])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(_, _, let detectedSource) = captureState else {
      Issue.record("Expected the newly pressed control")
      return
    }
    #expect(detectedSource == .button(.east))
  }

  @Test func updatePreservesCompareAndSwapAndSurfacesConflict() async throws {
    let original = makeProfile(name: "Original")
    let proposed = makeProfile(id: original.id, name: "Proposed")
    let gateway = RuntimeFacadeGatewayStub(
      snapshotPayload: snapshot(profiles: [original]),
      updateShouldConflict: true
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.updateRemappingProfile(proposed, expectedCurrent: original)

    #expect(await gateway.lastExpectedCurrent == original)
    let mutationState = await MainActor.run { viewModel.mutationState }
    guard case .conflict(let profileID) = mutationState else {
      Issue.record("Expected a compare-and-swap conflict")
      return
    }
    #expect(profileID == original.id)
    #expect(
      await MainActor.run { viewModel.lastError }
        == "This profile changed elsewhere. Reload or keep editing."
    )
  }

  @Test func mutationSuccessIdentifiesUpdateButNotActivationAsDraftSave() async {
    let original = makeProfile(name: "Original")
    let proposed = makeProfile(id: original.id, name: "Proposed")
    let gateway = RuntimeFacadeGatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.updateRemappingProfile(proposed, expectedCurrent: original)
    let saveState = await MainActor.run { viewModel.mutationState }
    guard case .succeeded(let profileID) = saveState else {
      Issue.record("Expected an identified profile update")
      return
    }
    #expect(profileID == original.id)

    await viewModel.activateRemappingProfile(id: original.id)
    let activationState = await MainActor.run { viewModel.mutationState }
    guard case .completed(.activate(let activatedID)) = activationState else {
      Issue.record("Expected activation to be separate from profile save")
      return
    }
    #expect(activatedID == original.id)
  }

  @Test func overlappingMutationsRejectTheSecondRequestWhileSaving() async {
    let original = makeProfile(name: "Original")
    let proposed = makeProfile(id: original.id, name: "Proposed")
    let ignored = makeProfile(id: original.id, name: "Ignored")
    let gateway = RuntimeFacadeGatewayStub(
      snapshotPayload: snapshot(profiles: [original]),
      updateDelayNanoseconds: 100_000_000
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    let first = Task { @MainActor in
      await viewModel.updateRemappingProfile(proposed, expectedCurrent: original)
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
    #expect(
      await MainActor.run { viewModel.activeMutationOperation == .update(profileID: original.id) }
    )

    let second = Task { @MainActor in
      await viewModel.updateRemappingProfile(ignored, expectedCurrent: original)
    }
    await second.value

    let rejectedState = await MainActor.run { viewModel.mutationState }
    guard case .error(let rejectionMessage) = rejectedState else {
      Issue.record("Expected the overlapping update to be rejected explicitly")
      return
    }
    #expect(rejectionMessage == "Another profile action is already in progress.")
    #expect(
      await MainActor.run { viewModel.lastMutationOperation == .update(profileID: original.id) }
    )

    await first.value

    #expect(await gateway.updateCallCount == 1)
    let mutationState = await MainActor.run { viewModel.mutationState }
    guard case .succeeded(let profileID) = mutationState else {
      Issue.record("Expected only the first update to complete")
      return
    }
    #expect(profileID == original.id)
  }

  @Test func rejectedCompatibilityIdentityDoesNotPublishRequestedValue() async {
    let gateway = RuntimeFacadeGatewayStub(setIdentityResult: false)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.setCompatibilityIdentity(.appleGameController)

    let state = await MainActor.run { viewModel.compatibilityState }
    guard case .error(let message) = state else {
      Issue.record("Expected a rejected identity to produce an error")
      return
    }
    #expect(message == "The selected controller output could not be enabled.")
    #expect(await MainActor.run { viewModel.compatibilityError } == message)
    #expect(await gateway.selectedIdentity == .sdl2_3)
  }

  @Test func resettingCompatibilityIdentityUsesTheScopedMutation() async {
    let gateway = RuntimeFacadeGatewayStub()
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.resetCompatibilityIdentity()

    #expect(await gateway.selectedIdentity == .sdl2_3)
    #expect(await gateway.setIdentityCallCount == 1)
  }

  @Test func compatibilitySuccessDoesNotInheritAnUnrelatedRuntimeError() async {
    let gateway = RuntimeFacadeGatewayStub(statusShouldFail: true)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let state = await MainActor.run { (viewModel.compatibilityState, viewModel.compatibilityError) }
    guard case .available = state.0 else {
      Issue.record("Expected compatibility identity loading to succeed")
      return
    }
    #expect(state.1 == nil)
    #expect(await MainActor.run { viewModel.lastError } != nil)
  }

  @Test func newerCompatibilitySelectionWinsOverAnOlderIdentityRead() async {
    let gateway = RuntimeFacadeGatewayStub(compatibilityReadDelayNanoseconds: 100_000_000)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let read = Task { @MainActor in await viewModel.loadCompatibilityIdentity() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.setCompatibilityIdentity(.appleGameController)
    await read.value

    let state = await MainActor.run { viewModel.compatibilityState }
    guard case .available(let identity) = state else {
      Issue.record("Expected the newer compatibility selection to remain authoritative")
      return
    }
    #expect(identity == .appleGameController)
  }

  @Test func compatibilitySelectionUpdatesTheStatusSummary() async {
    let gateway = RuntimeFacadeGatewayStub()
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()
    await viewModel.setCompatibilityIdentity(.appleGameController)

    let state = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = state else {
      Issue.record("Expected the status summary to remain available")
      return
    }
    #expect(status.compatibilityIdentity == .appleGameController)
    #expect(status.compatibilityLabel == "Apple GameController")
  }

  @Test func detectedSourceUsesCanonicalButtonDpadAndAxisOrder() {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    state.pressedButtons = ["Circle", "A"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.south))

    state.pressedButtons = ["D-pad Left"]
    #expect(RuntimePresentation.detectedSource(from: state) == .dpad(.left))

    state.pressedButtons = []
    state.leftStickX = -0.75
    #expect(
      RuntimePresentation.detectedSource(from: state) == .axisDirection(.leftStickX, .negative)
    )

    state.leftStickX = 0.2
    state.rightTrigger = 0.7
    #expect(
      RuntimePresentation.detectedSource(from: state) == .axisDirection(.rightTrigger, .positive)
    )

    state.rightTrigger = 0.2
    #expect(RuntimePresentation.detectedSource(from: state) == nil)
  }

  @Test func detectedSourceIncludesGenericAndDigitalControllerAliases() {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    state.pressedButtons = ["genericButton4"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.auxiliary4))

    state.pressedButtons = ["l2Digital"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.auxiliary1))

    state.pressedButtons = ["r2Digital"]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(.auxiliary2))
  }

  @Test func detectedSourceIgnoresReservedGuideAndHomeControls() {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    state.pressedButtons = ["Guide"]
    #expect(RuntimePresentation.detectedSource(from: state) == nil)

    state.pressedButtons = ["Home"]
    #expect(RuntimePresentation.detectedSource(from: state) == nil)
  }

  @Test func detectedTransitionUsesCanonicalAliasesAndAxisThresholds() {
    let previous = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    var current = previous
    current.pressedButtons = ["genericButton7"]
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current) == .button(.auxiliary7)
    )

    current.pressedButtons = []
    current.leftStickX = 0.75
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current)
        == .axisDirection(.leftStickX, .positive)
    )

    var held = current
    held.leftStickX = 0.8
    #expect(RuntimePresentation.detectedTransition(from: current, to: held) == nil)

    held.leftStickX = -0.8
    #expect(
      RuntimePresentation.detectedTransition(from: current, to: held)
        == .axisDirection(.leftStickX, .negative)
    )
  }

  @Test func detectedTransitionIgnoresReleaseOnlyChanges() {
    var previous = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    previous.pressedButtons = ["A", "B"]
    var current = previous
    current.pressedButtons = ["B"]

    #expect(RuntimePresentation.detectedTransition(from: previous, to: current) == nil)
  }

  private func makeProfile(id: UUID = UUID(), name: String = "Test Profile") -> RemappingProfile {
    RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
      ]
    )
  }

  private func snapshot(
    profiles: [RemappingProfile],
    activeProfiles: [ApplicationServiceRemappingActiveProfilePayload] = [],
    postEventAccess: RemappingPostEventAccessState = .granted
  ) -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: profiles,
      activeProfiles: activeProfiles,
      routes: [],
      postEventAccess: postEventAccess
    )
  }
}

private actor RuntimeFacadeGatewayStub: ApplicationServiceGateway {
  let statusPayload: ApplicationServiceStatusPayload
  let snapshotPayload: ApplicationServiceRemappingSnapshotPayload
  let statusShouldFail: Bool
  let inputState: DeviceInputState?
  let inputSequence: [DeviceInputState]?
  let updateShouldConflict: Bool
  let updateDelayNanoseconds: UInt64
  let setIdentityResult: Bool
  let compatibilityReadDelayNanoseconds: UInt64
  var lastExpectedCurrent: RemappingProfile?
  var lastInputSelector: RuntimeDeviceSelector?
  var updateCallCount = 0
  var inputReadCount = 0
  var setIdentityCallCount = 0
  var selectedIdentity: CompatibilityIdentity = .sdl2_3

  init(
    statusPayload: ApplicationServiceStatusPayload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    ),
    snapshotPayload: ApplicationServiceRemappingSnapshotPayload =
      ApplicationServiceRemappingSnapshotPayload(
        profiles: [],
        activeProfiles: [],
        routes: [],
        postEventAccess: .granted
      ),
    statusShouldFail: Bool = false,
    inputState: DeviceInputState? = nil,
    inputSequence: [DeviceInputState]? = nil,
    updateShouldConflict: Bool = false,
    updateDelayNanoseconds: UInt64 = 0,
    setIdentityResult: Bool = true,
    compatibilityReadDelayNanoseconds: UInt64 = 0
  ) {
    self.statusPayload = statusPayload
    self.snapshotPayload = snapshotPayload
    self.statusShouldFail = statusShouldFail
    self.inputState = inputState
    self.inputSequence = inputSequence
    self.updateShouldConflict = updateShouldConflict
    self.updateDelayNanoseconds = updateDelayNanoseconds
    self.setIdentityResult = setIdentityResult
    self.compatibilityReadDelayNanoseconds = compatibilityReadDelayNanoseconds
  }

  func status() throws -> ApplicationServiceStatusPayload {
    if statusShouldFail { throw ApplicationServiceClientError.timeout }
    return statusPayload
  }

  func virtualDeviceDiagnostics() throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload {
    ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      hidGamepads: []
    )
  }

  func requestPermissions() throws -> PermissionManager.Snapshot {
    PermissionManager.Snapshot(inputMonitoring: .granted, accessibility: .granted)
  }

  func deviceInputState(for selector: RuntimeDeviceSelector) throws -> DeviceInputState? {
    lastInputSelector = selector
    if let inputSequence, !inputSequence.isEmpty {
      let index = min(inputReadCount, inputSequence.count - 1)
      inputReadCount += 1
      return inputSequence[index]
    }
    return inputState
  }

  func remappingSnapshot() throws -> ApplicationServiceRemappingSnapshotPayload { snapshotPayload }

  func remappingProfile(id: UUID) throws -> RemappingProfile {
    guard let profile = snapshotPayload.profiles.first(where: { $0.id == id }) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return profile
  }

  func createRemappingProfile(_ profile: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func updateRemappingProfile(_ profile: RemappingProfile, expectedCurrent: RemappingProfile)
    async throws -> ApplicationServiceRemappingSnapshotPayload
  {
    updateCallCount += 1
    lastExpectedCurrent = expectedCurrent
    if updateDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: updateDelayNanoseconds) }
    if updateShouldConflict {
      throw ApplicationServiceRemappingRPCError(
        code: .profileUpdateConflict,
        message: "stale profile"
      )
    }
    return snapshotPayload
  }

  func importRemappingProfile(_ profile: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func deleteRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
    snapshotPayload
  }

  func activateRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
    snapshotPayload
  }

  func deactivateRemappingProfile(vendorID: UInt16, productID: UInt16) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func deactivateRemappingProfile(profileID: UUID) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func remappingPostEventAccess() throws -> RemappingPostEventAccessState {
    snapshotPayload.postEventAccess
  }

  func requestRemappingPostEventAccess() throws -> RemappingPostEventAccessState {
    snapshotPayload.postEventAccess
  }

  func compatibilityIdentity() async throws -> CompatibilityIdentity {
    let identity = selectedIdentity
    if compatibilityReadDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: compatibilityReadDelayNanoseconds)
    }
    return identity
  }

  func setCompatibilityIdentity(_ identity: CompatibilityIdentity) throws -> Bool {
    setIdentityCallCount += 1
    if setIdentityResult { selectedIdentity = identity }
    return setIdentityResult
  }
}
