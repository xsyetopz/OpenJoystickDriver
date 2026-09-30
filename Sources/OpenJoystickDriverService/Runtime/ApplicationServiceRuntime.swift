import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

@MainActor
package final class ApplicationServiceRuntime {
  private let permissionManager: PermissionManager
  private let dispatcher: VirtualOutputRouter
  private let remappingRouter: RemappingOutputRouter
  private let manager: DeviceManager
  private let bluetoothLECentral: Switch2BluetoothLECentral
  private let applicationServiceServer: ApplicationServiceServer
  private var systemPowerObserver: SystemPowerNotificationObserver?
  private var controllerRecordWatcher: ControllerRecordWatcher?
  private var systemPowerEventSession: DeviceManagerSystemPowerEventSession?
  private var started = false
  private var shutdownSignalSources: [DispatchSourceSignal] = []
  private var shutdownSignalHandler: (@MainActor @Sendable () -> Void)?

  package init() {
    let permissionManager = PermissionManager()
    let dispatcher = VirtualOutputRouter()
    let remappingProfileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let physicalOutputBridge = RemappingPhysicalOutputBridge()
    let remappingEngine = RemappingEventEngine(
      sink: CoreGraphicsSystemInputSink(access: postEventAccess),
      gamepadSink: dispatcher,
      physicalOutputSink: physicalOutputBridge
    )
    let remappingRouter = RemappingOutputRouter(
      library: remappingProfileLibrary,
      engine: remappingEngine,
      virtualOutput: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    let bluetoothLEHub = Switch2BluetoothLEHub()
    let manager = DeviceManager(
      dispatcher: remappingRouter,
      usbTransportProvider: OpenJoystickDriverUSBTransportProvider(),
      wirelessControllerDisconnector: BluetoothControllerDisconnector(),
      bluetoothLEHub: bluetoothLEHub
    )
    bluetoothLECentral = Switch2BluetoothLECentral(hub: bluetoothLEHub)
    physicalOutputBridge.attach(manager)
    let applicationServiceServer = ApplicationServiceServer(
      deviceManager: manager,
      permissionManager: permissionManager,
      dispatcher: dispatcher,
      remappingProfileLibrary: remappingProfileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess,
      userSpaceDispatcherFactory: Self.makeAutomaticUserSpaceDispatcher(context:)
    )

    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.remappingRouter = remappingRouter
    self.manager = manager
    self.applicationServiceServer = applicationServiceServer
  }

  package func start() throws {
    guard !started else { return }
    started = true

    setbuf(stdout, nil)
    serviceLog("[Service] Starting main-app service runtime")
    setupGracefulShutdown()
    do { try applicationServiceServer.start() } catch {
      cancelGracefulShutdown()
      started = false
      throw error
    }
    let manager = manager
    // Records apply before detection starts, so the first admission already uses them.
    let controllerRecordWatcher = ControllerRecordWatcher {
      Task { await manager.reloadControllerRecords() }
    }
    self.controllerRecordWatcher = controllerRecordWatcher
    controllerRecordWatcher.start()
    let systemPowerEventSession = DeviceManagerSystemPowerEventSession()
    self.systemPowerEventSession = systemPowerEventSession
    let systemPowerObserver = SystemPowerNotificationObserver { event in
      await deliverSystemPowerEvent(event, to: manager, session: systemPowerEventSession)
    }
    self.systemPowerObserver = systemPowerObserver
    systemPowerObserver.start()
    Task { await permissionManager.startPolling() }
    remappingRouter.startTicker()
    let bluetoothLECentral = bluetoothLECentral
    Task {
      await manager.start()
      bluetoothLECentral.start()
      _ = await applicationServiceServer.activateVirtualOutputBackendForCurrentDevices()
    }
  }

  /// Replaces `stop()` + `exit(0)` on SIGTERM/SIGINT.
  ///
  /// The menu-bar host uses this so AppKit can remove the status item before the
  /// process exits. Install the handler before `start()`.
  package func handleShutdownSignal(_ handler: @escaping @MainActor @Sendable () -> Void) {
    shutdownSignalHandler = handler
  }

  package func stop() async {
    guard started else { return }
    started = false

    cancelGracefulShutdown()
    controllerRecordWatcher?.stop()
    controllerRecordWatcher = nil
    let systemPowerObserver = systemPowerObserver
    self.systemPowerObserver = nil
    let systemPowerEventSession = systemPowerEventSession
    self.systemPowerEventSession = nil
    systemPowerEventSession?.invalidate()
    bluetoothLECentral.stop()
    if let systemPowerObserver {
      async let observerStop: Void = systemPowerObserver.stop()
      await applicationServiceServer.stop()
      await manager.stop()
      await observerStop
    } else {
      await applicationServiceServer.stop()
      await manager.stop()
    }
    do { try await remappingRouter.shutdown() } catch {
      serviceError("[Service] Remapping shutdown failed: \(error.localizedDescription)")
    }
    await permissionManager.stopPolling()
    serviceLog("[Service] Stopped")
  }

  private func serviceLog(_ message: String) { print(message) }

  private func serviceError(_ message: String) { fputs("\(message)\n", stderr) }

  private func setupGracefulShutdown() {
    guard shutdownSignalSources.isEmpty else { return }
    shutdownSignalSources = [SIGTERM, SIGINT].map { signalNumber in
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
      source.setEventHandler { [weak self] in
        Task { @MainActor in
          guard let self else { return }
          if let shutdownSignalHandler = self.shutdownSignalHandler {
            shutdownSignalHandler()
            return
          }
          self.serviceLog("[Service] Signal \(signalNumber) - stopping...")
          await self.stop()
          exit(0)
        }
      }
      signal(signalNumber, SIG_IGN)
      source.resume()
      return source
    }
  }

  private func cancelGracefulShutdown() {
    let sources = shutdownSignalSources
    shutdownSignalSources.removeAll()
    for source in sources { source.cancel() }
  }
}

private func deliverSystemPowerEvent(
  _ event: SystemPowerNotificationObserver.Event,
  to manager: DeviceManager,
  session: DeviceManagerSystemPowerEventSession
) async {
  let completion = RuntimePowerEventCompletion()
  await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
      completion.install(continuation)
      Task {
        switch event {
        case .willSleep: await manager.systemWillSleep(session: session)
        case .didWake: await manager.systemDidWake(session: session)
        }
        completion.finish()
      }
    }
  } onCancel: {
    completion.finish()
  }
}

/// Lets observer shutdown join its delivery task while a manager power call is still tearing down
/// controllers. The revoked runtime session rejects late actor entry; `DeviceManager.stop()`
/// clears the sleep state of a power operation that entered before invalidation.
private final class RuntimePowerEventCompletion: Sendable {
  private let state = Locked<(continuation: CheckedContinuation<Void, Never>?, isFinished: Bool)>(
    (nil, false)
  )

  func install(_ continuation: CheckedContinuation<Void, Never>) {
    let isFinished = state.withLock { state in
      if !state.isFinished { state.continuation = continuation }
      return state.isFinished
    }
    if isFinished { continuation.resume() }
  }

  func finish() {
    let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
      guard !state.isFinished else { return nil }
      state.isFinished = true
      defer { state.continuation = nil }
      return state.continuation
    }
    continuation?.resume()
  }
}
