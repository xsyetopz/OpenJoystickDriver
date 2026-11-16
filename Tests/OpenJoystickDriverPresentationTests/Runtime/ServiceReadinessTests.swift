import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverPresentation

struct ServiceReadinessTests {
  private static let build = BuildIdentity(
    semanticVersion: "0.6.0",
    appBundleVersion: "7",
    sourceCommit: "abc1234",
    sourceState: .clean
  )

  private static func answered(by build: BuildIdentity) -> RuntimeStatusState {
    .available(
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          buildIdentity: build,
          inputRead: .granted,
          inputInject: .granted,
          connectedDevices: []
        )
      )
    )
  }

  private static func input(
    _ status: RuntimeStatusState,
    listenerStopped: Bool = false,
    registration: ApplicationServiceRegistrationStatus? = nil
  ) -> ServiceReadinessInput {
    ServiceReadinessInput(
      status: status,
      listenerStopped: listenerStopped,
      registration: registration,
      appBuild: build
    )
  }

  @Test
  func everyStateHasItsOwnSymbolAndItsSymbolShapeDiffers() {
    let symbols = ServiceReadiness.allCases.map(\.symbolName)
    #expect(Set(symbols).count == ServiceReadiness.allCases.count)
    #expect(
      Set(symbols.map { $0.split(separator: ".").first.map(String.init) ?? "" }).count
        == symbols.count
    )
  }

  @Test(arguments: ServiceReadiness.allCases)
  func everyStateSentenceExistsInCatalog(state: ServiceReadiness) {
    #expect(OJDLocalized.string(state.messageKey) != state.messageKey)
  }

  @Test
  func everyStateHasDistinctSentence() {
    let keys = ServiceReadiness.allCases.map(\.messageKey)
    #expect(Set(keys).count == keys.count)
  }

  @Test
  func statusStillLoadingChecking() {
    #expect(ServiceReadiness.resolve(Self.input(.loading)) == .checking)
    #expect(
      ServiceReadiness.resolve(Self.input(.loading, registration: .requiresApproval)) == .checking
    )
  }

  @Test
  func serviceAnswersWithAppsBuildRunning() {
    let status = Self.answered(by: Self.build)
    #expect(ServiceReadiness.resolve(Self.input(status)) == .running)
    #expect(ServiceReadiness.resolve(Self.input(status, registration: .notRegistered)) == .running)
  }

  @Test
  func serviceOfAnotherBuildVersionMismatch() {
    let other = BuildIdentity(
      semanticVersion: "0.5.0",
      appBundleVersion: "7",
      sourceCommit: "abc1234",
      sourceState: .clean
    )
    #expect(ServiceReadiness.resolve(Self.input(Self.answered(by: other))) == .versionMismatch)
  }

  @Test
  func serviceDoesNotAnswerStoppedUnlessLoginItemExplainsIt() {
    let down = RuntimeStatusState.unavailable("down")
    #expect(ServiceReadiness.resolve(Self.input(down)) == .stopped)
    #expect(ServiceReadiness.resolve(Self.input(down, registration: .enabled)) == .stopped)
    #expect(
      ServiceReadiness.resolve(Self.input(down, registration: .notRegistered)) == .notInstalled
    )
    #expect(ServiceReadiness.resolve(Self.input(down, registration: .notFound)) == .notInstalled)
    #expect(
      ServiceReadiness.resolve(Self.input(down, registration: .requiresApproval)) == .needsApproval
    )
  }

  @Test
  func stoppedListenerAndFailedReadTheirOwnStates() {
    #expect(
      ServiceReadiness.resolve(Self.input(.unavailable("down"), listenerStopped: true))
        == .listenerStopped
    )
    #expect(ServiceReadiness.resolve(Self.input(.error("bad"))) == .readFailed)
  }

  @Test
  func onlyCheckingAndRunningNotProblems() {
    let quiet = ServiceReadiness.allCases.filter { !$0.isProblem }
    #expect(Set(quiet) == [.checking, .running])
  }
}
