import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct SetupCoordinatorTests {
  @Test
  func activeExtensionDoesNotSubmit() {
    let client = FakeSetupClient(status: Self.currentActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()

    #expect(coordinator.state == .active)
    #expect(client.requestCount == 0)
  }

  @Test
  func activeExtensionCanBeExplicitlyUninstalled() async {
    let client = FakeSetupClient(status: Self.currentActiveStatus, deactivationResult: .inactive)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()
    await coordinator.uninstall()

    #expect(coordinator.state == .needsActivation)
    #expect(client.deactivationRequestCount == 1)
  }

  @Test
  func launchForegroundAndRefreshSendNoActivationRequest() {
    let client = FakeSetupClient(status: Self.inactiveStatus, result: .awaitingApproval)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()
    coordinator.foreground()
    coordinator.refresh()

    #expect(coordinator.state == .needsActivation)
    #expect(client.requestCount == 0)
  }

  @Test
  func olderActiveExtensionWaitsForARepairClick() async {
    let client = FakeSetupClient(status: Self.olderActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()
    #expect(coordinator.state == .replacementNeeded)
    #expect(client.requestCount == 0)

    await coordinator.repair()
    #expect(coordinator.state == .active)
    #expect(client.requestCount == 1)
  }

  @Test
  func repairSubmitsOnceAndWaitsForApprovalAcrossReads() async {
    let client = FakeSetupClient(status: Self.inactiveStatus, result: .awaitingApproval)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.repair()
    coordinator.foreground()
    coordinator.refresh()

    #expect(coordinator.state == .needsApproval)
    #expect(client.requestCount == 1)
  }

  @Test
  func invalidEmbeddedBundleNeverSubmits() async {
    let client = FakeSetupClient(
      status: ExtensionStatus(bundle: .invalid("wrong"), registration: .absent)
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()
    await coordinator.repair()

    #expect(coordinator.state == .invalid)
    #expect(client.requestCount == 0)
  }

  @Test
  func historicalIntegerBuildSendsNoRequestAtLaunch() {
    let client = FakeSetupClient(
      status: ExtensionStatus(
        bundle: .present,
        registration: .active("historical"),
        embedded: Self.currentFacts,
        installed: ExtensionVersionFacts(
          extensionID: USBDriverKitExtensionConfiguration.extensionID,
          shortVersion: "0.5.0-beta.1",
          buildVersion: "500001"
        )
      )
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()
    coordinator.foreground()
    coordinator.refresh()

    #expect(client.requestCount == 0)
  }

  @Test
  func currentActiveExtensionDoesNotRequestReplacement() async {
    let client = FakeSetupClient(status: Self.currentActiveStatus)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()
    await coordinator.repair()

    #expect(client.requestCount == 0)
    #expect(coordinator.state == .active)
  }

  @Test
  func unknownInstalledVersionNeedsAReplacementClick() {
    let client = FakeSetupClient(
      status: ExtensionStatus(
        bundle: .present,
        registration: .active("unknown"),
        embedded: Self.currentFacts,
        installed: nil
      )
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()

    #expect(coordinator.state == .replacementNeeded)
    #expect(client.requestCount == 0)
  }

  @Test
  func unreadableRegistrationIsUnavailableAndNeverSubmits() async {
    let client = FakeSetupClient(
      status: ExtensionStatus(
        bundle: .present,
        registration: .unavailable("probe failed"),
        embedded: Self.currentFacts
      )
    )
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    coordinator.launch()
    await coordinator.repair()

    #expect(coordinator.state == .unavailable("probe failed"))
    #expect(client.requestCount == 0)
  }

  @Test
  func requestOutcomesHaveOneStateEach() async {
    let failure = SystemExtensionRequestFailure(
      domain: "OSSystemExtensionErrorDomain",
      code: 4,
      text: "Extension not found in App bundle"
    )
    let cases: [(SystemExtensionSetupRequestResult, SystemExtensionSetupState)] = [
      (.timedOut, .timedOut), (.cancelled, .cancelled), (.failed(failure), .failed(failure)),
      (.awaitingApproval, .needsApproval), (.inactive, .needsActivation),
    ]
    for (result, expected) in cases {
      let client = FakeSetupClient(status: Self.inactiveStatus, result: result)
      let coordinator = SystemExtensionSetupCoordinator(client: client)

      await coordinator.repair()
      coordinator.foreground()

      #expect(coordinator.state == expected)
      #expect(client.requestCount == 1)
    }
  }

  @Test
  func stateIsRunningWhileTheRequestIsPendingAndASecondClickIsVisible() async {
    let client = FakeSetupClient(status: Self.inactiveStatus, result: .active)
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    let first = Task { await coordinator.repair() }
    await Task.yield()
    #expect(coordinator.state == .running)
    await coordinator.repair()
    #expect(coordinator.state == .running)
    await first.value

    #expect(coordinator.state == .active)
    #expect(client.requestCount == 1)
  }

  @Test
  func repairAfterFailureSubmitsAgain() async {
    let failure = SystemExtensionRequestFailure(domain: "d", code: 1, text: "t")
    let client = FakeSetupClient(status: Self.inactiveStatus, results: [.failed(failure), .active])
    let coordinator = SystemExtensionSetupCoordinator(client: client)

    await coordinator.repair()
    await coordinator.repair()

    #expect(coordinator.state == .active)
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
    extensionID: USBDriverKitExtensionConfiguration.extensionID,
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
      extensionID: USBDriverKitExtensionConfiguration.extensionID,
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
    return results.isEmpty ? .timedOut : results.removeFirst()
  }

  func requestDeactivation() async -> SystemExtensionSetupRequestResult {
    await Task.yield()
    deactivationRequestCount += 1
    return deactivationResult
  }
}
