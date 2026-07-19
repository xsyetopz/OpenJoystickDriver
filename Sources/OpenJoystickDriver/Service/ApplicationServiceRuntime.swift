import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverRelay

final class ApplicationServiceRuntime: @unchecked Sendable {
  private let permissionManager: PermissionManager
  private let driverKitDispatcher: DriverKitOutputDispatcher
  private let dispatcher: CompatibilityOutputDispatcher
  private let manager: DeviceManager
  private let applicationServiceServer: ApplicationServiceServer
  private let foregroundConsumerOutputMonitor: ForegroundConsumerOutputMonitor
  private let stateLock = NSLock()
  private var started = false

  init() {
    let permissionManager = PermissionManager()
    let driverKitDispatcher = DriverKitOutputDispatcher()
    let dispatcher = CompatibilityOutputDispatcher()
    let manager = DeviceManager(dispatcher: dispatcher)
    let applicationServiceServer = ApplicationServiceServer(
      deviceManager: manager,
      permissionManager: permissionManager,
      dispatcher: dispatcher,
      driverKitDispatcher: driverKitDispatcher
    )

    self.permissionManager = permissionManager
    self.driverKitDispatcher = driverKitDispatcher
    self.dispatcher = dispatcher
    self.manager = manager
    self.applicationServiceServer = applicationServiceServer
    self.foregroundConsumerOutputMonitor = ForegroundConsumerOutputMonitor(deviceManager: manager) {
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
    serviceLog("[Service] DriverKit integrity relay: diagnostic probes only")
    serviceLog("[Service] Starting main-app service runtime")
    manager.setupGracefulShutdown(label: "Service")
    Task { await permissionManager.startPolling() }
    do { try applicationServiceServer.start() } catch {
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
    await driverKitDispatcher.stopBackend()
    await permissionManager.stopPolling()
    serviceLog("[Service] Stopped")
  }

  private func serviceLog(_ message: String) {
    print(message)
    NSLog("%@", message)
  }
}
