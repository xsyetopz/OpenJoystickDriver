import Foundation
import Testing

@testable import OpenJoystickDriver

@MainActor struct SetupCoordinatorTests {
  @Test func activeExtensionDoesNotSubmit() async {
    let client = FakeSetupClient(status: Self.currentActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(coordinator.state == SystemExtensionSetupState.active)
    #expect(client.requestCount == 0)
  }

  @Test func missingRegistrationSubmitsOnceAndWaitsForApproval() async {
    let client = FakeSetupClient(
      status: Self.inactiveStatus,
      result: SystemExtensionSetupRequestResult.awaitingApproval
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    await coordinator.foreground()
    await coordinator.refresh()

    #expect(coordinator.state == SystemExtensionSetupState.awaitingApproval)
    #expect(client.requestCount == 1)
  }

  @Test func repairRetriesAfterFailureAndReplacementUsesActivationRequest() async {
    let client = FakeSetupClient(status: Self.inactiveStatus, results: [.failed, .active])
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    #expect(coordinator.state == SystemExtensionSetupState.failed)
    await coordinator.repair()

    #expect(coordinator.state == SystemExtensionSetupState.active)
    #expect(client.requestCount == 2)
  }

  @Test func invalidEmbeddedBundleNeverSubmits() async {
    let client = FakeSetupClient(
      status: ExtensionStatus(bundle: .invalid("wrong"), registration: .absent)
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(coordinator.state == SystemExtensionSetupState.invalid)
    #expect(client.requestCount == 0)
  }

  @Test func unknownInstalledVersionFailsClosedWithoutSubmittingAgain() async {
    let client = FakeSetupClient(
      status: ExtensionStatus(
        bundle: .present,
        registration: .active("unknown"),
        embedded: Self.currentFacts,
        installed: nil
      )
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(coordinator.state == SystemExtensionSetupState.failed)
    #expect(client.requestCount == 0)
  }

  @Test func timedOutActivationIsTerminalUntilRepair() async {
    let client = FakeSetupClient(status: Self.inactiveStatus, result: .timedOut)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    await coordinator.foreground()

    #expect(coordinator.state == SystemExtensionSetupState.failed)
    #expect(client.requestCount == 1)
  }

  @Test func olderActiveExtensionRequestsOneReplacement() async {
    let client = FakeSetupClient(status: Self.olderActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(client.requestCount == 1)
    #expect(coordinator.state == SystemExtensionSetupState.active)
  }

  @Test func historicalIntegerBuildDoesNotCreateReplacementLoop() async {
    let client = FakeSetupClient(
      status: ExtensionStatus(
        bundle: .present,
        registration: .active("historical"),
        embedded: Self.currentFacts,
        installed: ExtensionVersionFacts(
          bundleIdentifier: ExtensionProbe.bundleIdentifier,
          shortVersion: "0.5.0-beta.1",
          buildVersion: "500001"
        )
      )
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    await coordinator.foreground()
    await coordinator.refresh()

    #expect(client.requestCount == 1)
  }

  @Test func currentActiveExtensionDoesNotRequestReplacement() async {
    let client = FakeSetupClient(status: Self.currentActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(client.requestCount == 0)
    #expect(coordinator.state == SystemExtensionSetupState.active)
  }

  @Test func cancelledActivationIsTerminalUntilExplicitRepair() async {
    let client = FakeSetupClient(status: Self.inactiveStatus, results: [.cancelled, .active])
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    await coordinator.refresh()
    #expect(coordinator.state == SystemExtensionSetupState.failed)
    #expect(client.requestCount == 1)

    await coordinator.repair()
    #expect(coordinator.state == SystemExtensionSetupState.active)
    #expect(client.requestCount == 2)
  }

  @Test func submissionCompletionIsOneShotAcrossTerminalEvents() {
    let gate = SystemExtensionSubmissionCompletionGate()

    #expect(gate.accept())
    #expect(!gate.accept())
    #expect(!gate.accept())
  }

  @Test func submissionCompletionGateWinsConcurrentRaces() async {
    let gate = SystemExtensionSubmissionCompletionGate()
    let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
      for _ in 0..<100 { group.addTask { gate.accept() } }
      var count = 0
      for await result in group where result { count += 1 }
      return count
    }

    #expect(accepted == 1)
  }

  @Test func cancellationBeforeStartPreventsSubmission() {
    let state = SystemExtensionRequestState()
    let submission = FakeSubmission()

    state.cancel()

    #expect(!state.start(submission))
    #expect(submission.startCount == 0)
    #expect(submission.cancelCount == 0)
  }

  @Test func actualSubmissionBoundaryCompletesOnceUnderConcurrentRaces() async {
    let counter = LockedCount()
    let submission = SystemExtensionSubmission(mode: .activation) { _ in counter.increment() }

    await withTaskGroup(of: Void.self) { group in
      group.addTask { submission.cancel() }
      group.addTask { submission.timeout() }
      group.addTask { submission.completeForTesting(.active) }
    }

    #expect(counter.value == 1)
  }

  private static let activeStatus = ExtensionStatus(
    bundle: .present,
    registration: .active("active")
  )
  private static let inactiveStatus = ExtensionStatus(
    bundle: .present,
    registration: .inactive("inactive")
  )
  private static let currentFacts = ExtensionVersionFacts(
    bundleIdentifier: ExtensionProbe.bundleIdentifier,
    shortVersion: "0.5.0-beta.3",
    buildVersion: "0.5.0b3"
  )
  private static let currentActiveStatus = ExtensionStatus(
    bundle: .present,
    registration: .active("current"),
    embedded: currentFacts,
    installed: currentFacts
  )
  private static let olderActiveStatus = ExtensionStatus(
    bundle: .present,
    registration: .active("older"),
    embedded: currentFacts,
    installed: ExtensionVersionFacts(
      bundleIdentifier: ExtensionProbe.bundleIdentifier,
      shortVersion: "0.5.0-beta.2",
      buildVersion: "0.5.0b2"
    )
  )
}

private final class FakeSetupClient: @unchecked Sendable, SystemExtensionSetupClient {
  let status: ExtensionStatus
  var results: [SystemExtensionSetupRequestResult]
  private(set) var requestCount = 0

  init(
    status: ExtensionStatus,
    result: SystemExtensionSetupRequestResult = .active,
    results: [SystemExtensionSetupRequestResult]? = nil
  ) {
    self.status = status
    self.results = results ?? [result]
  }

  func inspect() -> ExtensionStatus { status }

  func requestActivation() async -> SystemExtensionSetupRequestResult {
    await Task.yield()
    requestCount += 1
    return results.isEmpty ? .failed : results.removeFirst()
  }
}

private final class FakeSubmission: SystemExtensionSubmissionControlling, @unchecked Sendable {
  private(set) var startCount = 0
  private(set) var cancelCount = 0

  func start() { startCount += 1 }
  func cancel() { cancelCount += 1 }
}

private final class LockedCount: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}
