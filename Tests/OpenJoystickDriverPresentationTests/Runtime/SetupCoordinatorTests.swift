import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct SetupCoordinatorTests {
  @Test
  func activeExtensionDoesNotSubmit() async {
    let client = FakeSetupClient(status: Self.currentActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(coordinator.state == SystemExtensionSetupState.active)
    #expect(client.requestCount == 0)
  }

  @Test
  func activeExtensionCanBeExplicitlyUninstalled() async {
    let client = FakeSetupClient(status: Self.currentActiveStatus, deactivationResult: .inactive)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    await coordinator.uninstall()

    #expect(coordinator.state == .needsActivation)
    #expect(client.deactivationRequestCount == 1)
  }

  @Test
  func missingRegistrationSubmitsOnceAndWaitsForApproval() async {
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

  @Test
  func repairRetriesAfterFailureAndReplacementUsesActivationRequest() async {
    let client = FakeSetupClient(status: Self.inactiveStatus, results: [.failed, .active])
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    #expect(coordinator.state == SystemExtensionSetupState.failed)
    await coordinator.repair()

    #expect(coordinator.state == SystemExtensionSetupState.active)
    #expect(client.requestCount == 2)
  }

  @Test
  func invalidEmbeddedBundleNeverSubmits() async {
    let client = FakeSetupClient(
      status: ExtensionStatus(bundle: .invalid("wrong"), registration: .absent)
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(coordinator.state == SystemExtensionSetupState.invalid)
    #expect(client.requestCount == 0)
  }

  @Test
  func unknownInstalledVersionFailsClosedWithoutSubmittingAgain() async {
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

  @Test
  func timedOutActivationIsTerminalUntilRepair() async {
    let client = FakeSetupClient(status: Self.inactiveStatus, result: .timedOut)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()
    await coordinator.foreground()

    #expect(coordinator.state == SystemExtensionSetupState.failed)
    #expect(client.requestCount == 1)
  }

  @Test
  func olderActiveExtensionRequestsOneReplacement() async {
    let client = FakeSetupClient(status: Self.olderActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(client.requestCount == 1)
    #expect(coordinator.state == SystemExtensionSetupState.active)
  }

  @Test
  func historicalIntegerBuildDoesNotCreateReplacementLoop() async {
    let client = FakeSetupClient(
      status: ExtensionStatus(
        bundle: .present,
        registration: .active("historical"),
        embedded: Self.currentFacts,
        installed: ExtensionVersionFacts(
          bundleIdentifier: USBDriverKitExtensionConfiguration.bundleIdentifier,
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

  @Test
  func currentActiveExtensionDoesNotRequestReplacement() async {
    let client = FakeSetupClient(status: Self.currentActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.launch()

    #expect(client.requestCount == 0)
    #expect(coordinator.state == SystemExtensionSetupState.active)
  }

  @Test
  func cancelledActivationIsTerminalUntilExplicitRepair() async {
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

  private static let activeStatus = ExtensionStatus(
    bundle: .present,
    registration: .active("active")
  )
  private static let inactiveStatus = ExtensionStatus(
    bundle: .present,
    registration: .inactive("inactive")
  )
  private static let currentFacts = ExtensionVersionFacts(
    bundleIdentifier: USBDriverKitExtensionConfiguration.bundleIdentifier,
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
      bundleIdentifier: USBDriverKitExtensionConfiguration.bundleIdentifier,
      shortVersion: "0.5.0-beta.2",
      buildVersion: "0.5.0b2"
    )
  )
}

final class FakeSetupClient: @unchecked Sendable, SystemExtensionSetupClient {
  let status: ExtensionStatus
  var results: [SystemExtensionSetupRequestResult]
  private(set) var requestCount = 0
  private(set) var deactivationRequestCount = 0
  let deactivationResult: SystemExtensionSetupRequestResult

  init(
    status: ExtensionStatus,
    result: SystemExtensionSetupRequestResult = .active,
    results: [SystemExtensionSetupRequestResult]? = nil,
    deactivationResult: SystemExtensionSetupRequestResult = .inactive
  ) {
    self.status = status
    self.results = results ?? [result]
    self.deactivationResult = deactivationResult
  }

  func inspect() -> ExtensionStatus { status }

  func requestActivation() async -> SystemExtensionSetupRequestResult {
    await Task.yield()
    requestCount += 1
    return results.isEmpty ? .failed : results.removeFirst()
  }

  func requestDeactivation() async -> SystemExtensionSetupRequestResult {
    await Task.yield()
    deactivationRequestCount += 1
    return deactivationResult
  }
}
