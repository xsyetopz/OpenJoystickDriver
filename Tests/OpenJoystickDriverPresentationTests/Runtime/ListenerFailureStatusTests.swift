import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.serialized, .removingTemporarySockets)
struct ListenerFailureStatusTests {
  private let failure = ServiceListenerFailure(
    errorNumber: EBADF,
    time: Date(timeIntervalSince1970: 1_800_000_000),
    process: .current
  )

  private func makeViewModel(
    _ state: ServiceListenerState,
    gateway: GatewayStub
  ) async -> RuntimeViewModel {
    await MainActor.run { RuntimeViewModel(gateway: gateway, listenerState: state) }
  }

  private func statusMessage(_ viewModel: RuntimeViewModel) async -> String? {
    let state = await MainActor.run { viewModel.statusState }
    if case .unavailable(let message) = state { return message }
    return nil
  }

  @Test
  func statusLineAndBannerShowFailureInProcessAtOnce() async {
    let state = ServiceListenerState()
    let gateway = GatewayStub(statusShouldFail: true, statusError: .notConnected)
    let viewModel = await makeViewModel(state, gateway: gateway)

    state.set(failure)
    await waitUntil("the status line shows the failure") {
      let shown = await MainActor.run { viewModel.listenerFailure }
      let message = await statusMessage(viewModel)
      return shown == failure && message == failure.localizedSummary
    }

    let message = await statusMessage(viewModel)
    #expect(message?.contains("E2034") == true)
    #expect(message?.contains(ErrorCode.requestListenerStopped.localizedExplanation) == true)
    #expect(message?.contains(String(EBADF)) == true)
    let problems = await MainActor.run {
      MainWindowProblem.current(
        permissions: viewModel.permissionState,
        status: viewModel.statusState,
        driver: .active,
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: viewModel.listenerFailure
      )
    }
    #expect(problems.first == .service(.listenerStopped, failure.localizedSummary))
    #expect(problems.first?.action == .restartListener)
  }

  @Test
  func realServerThatStopsAcceptingShowsE2034InModelAndBanner() async throws {
    let socketPath = temporarySocketPath()
    let statusResult = try JSONEncoder().encode(
      try JSONEncoder().encode(
        ApplicationServiceStatusPayload(
          inputRead: .granted,
          inputInject: .granted,
          connectedDevices: [],
          userSpaceVirtualDeviceEnabled: true
        )
      )
    )
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        guard request.method == ApplicationServiceRPCMethod.getStatus.rawValue else {
          return LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)")
        }
        return LocalServiceRPCResponse(result: statusResult, error: nil)
      }
    )
    let state = ServiceListenerState()
    server.listenerFailureChanged = { state.set($0) }
    server.report = { _ in }
    let failing = FailingAccept()
    server.acceptConnection = { descriptor in
      if failing.isOn {
        errno = EBADF
        return -1
      }
      return Darwin.accept(descriptor, nil, nil)
    }
    try server.start()
    defer {
      server.stop()
      try? ServiceListenerFailure.clear(socketPath: socketPath)
    }
    let gateway = ApplicationServiceClientGateway(
      client: ApplicationServiceClient(socketPath: socketPath)
    )
    let viewModel = await MainActor.run {
      RuntimeViewModel(
        gateway: gateway,
        systemExtensionSetup: SystemExtensionSetupCoordinator(
          client: FakeSetupClient(
            status: ExtensionStatus(bundle: .present, registration: .inactive("inactive"))
          )
        ),
        listenerState: state
      )
    }
    await viewModel.refresh()
    let before = await MainActor.run { viewModel.statusState }
    guard case .available = before else {
      Issue.record("Expected the service to answer before the failure")
      return
    }

    failing.isOn = true
    let client = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = try LocalServiceRPCTransport.socketAddress(path: socketPath)
    _ = withUnsafePointer(to: &address) {
      unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        unsafe Darwin.connect(
          client,
          $0,
          LocalServiceRPCTransport.socketAddressLength(path: socketPath)
        )
      }
    }
    defer { Darwin.close(client) }

    await waitUntil("the model shows the failure") {
      let shown = await MainActor.run { viewModel.statusState }
      switch shown {
      case .unavailable(let message), .error(let message): return message.contains("E2034")
      default: return false
      }
    }
    let shown = await MainActor.run { viewModel.statusState }
    let message: String
    switch shown {
    case .unavailable(let text), .error(let text): message = text
    default: message = ""
    }
    #expect(message.contains(ErrorCode.requestListenerStopped.localizedExplanation))
    #expect(message.contains(String(EBADF)))
    let problems = await MainActor.run {
      MainWindowProblem.current(
        permissions: viewModel.permissionState,
        status: viewModel.statusState,
        driver: .active,
        extensionRouteConnected: true,
        liveUpdatesFallbackReason: nil,
        listenerFailure: viewModel.listenerFailure
      )
    }
    #expect(problems.first == .service(.listenerStopped, message))
  }

  @Test
  func withoutFailureStatusLineKeepsClientMessage() async {
    let gateway = GatewayStub(statusShouldFail: true, statusError: .notConnected)
    let viewModel = await makeViewModel(ServiceListenerState(), gateway: gateway)

    await viewModel.refresh()

    let message = await statusMessage(viewModel)
    #expect(
      message == RuntimePresentation.userFacingError(ApplicationServiceClientError.notConnected)
    )
  }

  @Test
  func restartingListenerClearsFailure() async {
    let state = ServiceListenerState()
    state.setRestart { state.set(nil) }
    let gateway = GatewayStub(statusShouldFail: true, statusError: .notConnected)
    let viewModel = await makeViewModel(state, gateway: gateway)
    state.set(failure)
    await waitUntil("the failure shows") {
      await MainActor.run { viewModel.listenerFailure } == failure
    }

    await viewModel.restartListener()

    await waitUntil("the failure clears") {
      await MainActor.run { viewModel.listenerFailure } == nil
    }
    #expect(state.failure == nil)
  }

  @Test
  func restartThatFailsKeepsFailureAndSaysWhy() async {
    let state = ServiceListenerState()
    state.setRestart { throw LocalServiceRPCError.connectionFailed(EADDRINUSE) }
    let gateway = GatewayStub(statusShouldFail: true, statusError: .notConnected)
    let viewModel = await makeViewModel(state, gateway: gateway)
    state.set(failure)
    await waitUntil("the failure shows") {
      await MainActor.run { viewModel.listenerFailure } == failure
    }

    await viewModel.restartListener()

    let message = await statusMessage(viewModel)
    #expect(message?.contains(String(EADDRINUSE)) == true)
    #expect(message?.contains(failure.localizedSummary) == true)
    #expect(await MainActor.run { viewModel.listenerFailure } == failure)
  }
}

private final class FailingAccept: @unchecked Sendable {
  private let lock = NSLock()
  private var on = false

  var isOn: Bool {
    get { lock.withLock { on } }
    set { lock.withLock { on = newValue } }
  }
}
