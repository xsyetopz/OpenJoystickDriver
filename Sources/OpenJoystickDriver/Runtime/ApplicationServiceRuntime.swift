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
      postEventAccess: postEventAccess,
      initializeCompatibilityBackend: false
    )

    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.remappingRouter = remappingRouter
    self.manager = manager
    self.applicationServiceServer = applicationServiceServer
  }

  func start() throws {
    let shouldStart = stateLock.withLock {
      guard !started else { return false }
      started = true
      return true
    }
    guard shouldStart else { return }

    setbuf(stdout, nil)
    serviceLog("[Service] Starting main-app service runtime")
    setupGracefulShutdown()
    do { try applicationServiceServer.start() } catch {
      cancelGracefulShutdown()
      stateLock.withLock { started = false }
      throw error
    }
    Task { await permissionManager.startPolling() }
    remappingRouter.startTicker()
    Task {
      await manager.start()
      _ = await applicationServiceServer.activateCompatibilityBackendForCurrentDevices()
    }
  }

  func stop() async {
    let shouldStop = stateLock.withLock {
      guard started else { return false }
      started = false
      return true
    }
    guard shouldStop else { return }

    cancelGracefulShutdown()
    await applicationServiceServer.stop()
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

#if canImport(SwiftUI)
  extension ApplicationServiceRuntime: InputTestDeviceGateway {
    func inputState(for selector: RuntimeDeviceSelector) async throws -> DeviceInputState? {
      let identifier = DeviceIdentifier(vendorID: selector.vendorID, productID: selector.productID)
      return await manager.inputState(
        for: identifier,
        runtimeIdentifier: selector.runtimeIdentifier
      )
    }

    func sendRumble(
      for selector: RuntimeDeviceSelector,
      left: UInt8,
      right: UInt8,
      leftTrigger: UInt8,
      rightTrigger: UInt8,
      durationMilliseconds: Int
    ) async throws -> Bool {
      let identifier = DeviceIdentifier(vendorID: selector.vendorID, productID: selector.productID)
      return await manager.sendRumble(
        for: identifier,
        runtimeIdentifier: selector.runtimeIdentifier,
        left: left,
        right: right,
        lt: leftTrigger,
        rt: rightTrigger,
        durationMs: durationMilliseconds
      )
    }

    func setPlayerIndicator(for selector: RuntimeDeviceSelector, indicator: PhysicalPlayerIndicator)
      async throws -> Bool
    {
      let identifier = DeviceIdentifier(vendorID: selector.vendorID, productID: selector.productID)
      return await manager.sendPlayerIndicator(
        for: identifier,
        runtimeIdentifier: selector.runtimeIdentifier,
        indicator: indicator
      )
    }

    func setColor(for selector: RuntimeDeviceSelector, red: UInt8, green: UInt8, blue: UInt8)
      async throws -> Bool
    {
      let identifier = DeviceIdentifier(vendorID: selector.vendorID, productID: selector.productID)
      return await manager.setPhysicalColor(
        for: identifier,
        runtimeIdentifier: selector.runtimeIdentifier,
        red: red,
        green: green,
        blue: blue
      )
    }

    func setBrightness(for selector: RuntimeDeviceSelector, brightness: UInt8) async throws -> Bool
    {
      let identifier = DeviceIdentifier(vendorID: selector.vendorID, productID: selector.productID)
      return await manager.setPhysicalBrightness(
        for: identifier,
        runtimeIdentifier: selector.runtimeIdentifier,
        brightness: brightness
      )
    }
  }
#endif
