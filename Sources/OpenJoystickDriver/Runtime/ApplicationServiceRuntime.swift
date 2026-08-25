import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

final class ApplicationServiceRuntime: @unchecked Sendable {
  private let permissionManager: PermissionManager
  private let dispatcher: CompatibilityOutputDispatcher
  private let remappingRouter: RemappingOutputRouter
  private let manager: DeviceManager
  private let applicationServiceServer: ApplicationServiceServer
  private let stateLock = NSLock()
  private var started = false
  private var shutdownSignalSources: [DispatchSourceSignal] = []

  init() {
    let permissionManager = PermissionManager()
    let dispatcher = CompatibilityOutputDispatcher()
    let remappingProfileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingEngine = RemappingEventEngine(
      sink: CoreGraphicsSystemInputSink(access: postEventAccess)
    )
    let remappingRouter = RemappingOutputRouter(
      library: remappingProfileLibrary,
      engine: remappingEngine,
      compatibility: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    let manager = DeviceManager(
      dispatcher: remappingRouter,
      usbTransportProvider: OpenJoystickDriverUSBTransportProvider()
    )
    let applicationServiceServer = ApplicationServiceServer(
      deviceManager: manager,
      permissionManager: permissionManager,
      dispatcher: dispatcher,
      remappingProfileLibrary: remappingProfileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess
    )

    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.remappingRouter = remappingRouter
    self.manager = manager
    self.applicationServiceServer = applicationServiceServer
  }

  func start() {
    let shouldStart = stateLock.withLock {
      guard !started else { return false }
      started = true
      return true
    }
    guard shouldStart else { return }

    setbuf(stdout, nil)
    serviceLog("[Service] Starting main-app service runtime")
    setupGracefulShutdown()
    Task { await permissionManager.startPolling() }
    remappingRouter.startTicker()
    do { try applicationServiceServer.start() } catch {
      serviceError("[Service] RPC socket startup failed: \(error.localizedDescription)")
    }
    Task { await manager.start() }
  }

  func stop() async {
    let shouldStop = stateLock.withLock {
      guard started else { return false }
      started = false
      return true
    }
    guard shouldStop else { return }

    cancelGracefulShutdown()
    applicationServiceServer.stop()
    await manager.stop()
    do { try await remappingRouter.shutdown() } catch {
      serviceError("[Service] Remapping shutdown failed: \(error.localizedDescription)")
    }
    await permissionManager.stopPolling()
    serviceLog("[Service] Stopped")
  }

  private func serviceLog(_ message: String) { print(message) }

  private func serviceError(_ message: String) { fputs("\(message)\n", stderr) }

  private func setupGracefulShutdown() {
    stateLock.withLock {
      guard shutdownSignalSources.isEmpty else { return }
      shutdownSignalSources = [SIGTERM, SIGINT].map { signalNumber in
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { [weak self] in
          guard let self else { return }
          serviceLog("[Service] Signal \(signalNumber) - stopping...")
          Task {
            await self.stop()
            exit(0)
          }
        }
        signal(signalNumber, SIG_IGN)
        source.resume()
        return source
      }
    }
  }

  private func cancelGracefulShutdown() {
    let sources = stateLock.withLock {
      defer { shutdownSignalSources.removeAll() }
      return shutdownSignalSources
    }
    for source in sources { source.cancel() }
  }
}
