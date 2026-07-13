import Foundation
import OpenJoystickDriverKit

final class ApplicationServiceRuntime: @unchecked Sendable {
  private let permissionManager: PermissionManager
  private let dextDispatcher: DextOutputDispatcher
  private let dispatcher: CompositeOutputDispatcher
  private let manager: DeviceManager
  private let applicationServiceServer: ApplicationServiceServer
  private let foregroundConsumerOutputMonitor: ForegroundConsumerOutputMonitor
  private let stateLock = NSLock()
  private var started = false

  init() {
    let permissionManager = PermissionManager()
    let dextDispatcher = DextOutputDispatcher()
    let dispatcher = CompositeOutputDispatcher(primary: dextDispatcher)
    let manager = DeviceManager(dispatcher: dispatcher)
    let applicationServiceServer = ApplicationServiceServer(
      deviceManager: manager,
      permissionManager: permissionManager,
      dispatcher: dispatcher,
      dextDispatcher: dextDispatcher
    )

    self.permissionManager = permissionManager
    self.dextDispatcher = dextDispatcher
    self.dispatcher = dispatcher
    self.manager = manager
    self.applicationServiceServer = applicationServiceServer
    self.foregroundConsumerOutputMonitor = ForegroundConsumerOutputMonitor(
      deviceManager: manager
    ) {
      frontmostBundleRootPath,
      effectiveConsumerBundleRoots,
      observedConsumerBundleRoots,
      activeRouteToken in
      await applicationServiceServer.applyForegroundCompatibilityRoutingUpdate(
        frontmostBundleRootPath: frontmostBundleRootPath,
        effectiveConsumerBundleRoots: effectiveConsumerBundleRoots,
        observedConsumerBundleRoots: observedConsumerBundleRoots,
        activeRouteToken: activeRouteToken
      )
    }
  }

  func start() {
    let shouldStart = stateLock.withLock {
      guard !started else { return false }
      started = true
      return true
    }
    guard shouldStart else { return }

    setbuf(stdout, nil)
    serviceLog("[Service] DriverKit output: on-demand (managed by Mode)")
    serviceLog("[Service] Starting main-app service runtime")
    manager.setupGracefulShutdown(label: "Service")
    Task { await permissionManager.startPolling() }
    do {
      try applicationServiceServer.start()
    } catch {
      serviceLog("[Service] RPC socket startup failed: \(error.localizedDescription)")
    }
    foregroundConsumerOutputMonitor.start()
    Task { await manager.start() }
  }

  func stop() async {
    let shouldStop = stateLock.withLock {
      guard started else { return false }
      started = false
      return true
    }
    guard shouldStop else { return }

    foregroundConsumerOutputMonitor.stop()
    applicationServiceServer.stop()
    await manager.stop()
    await permissionManager.stopPolling()
    serviceLog("[Service] Stopped")
  }

  private func serviceLog(_ message: String) {
    print(message)
    NSLog("%@", message)
  }
}
