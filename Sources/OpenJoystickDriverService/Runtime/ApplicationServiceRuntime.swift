import Darwin
import Foundation
package import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform
import OpenJoystickDriverUSB

/// Composes and runs the service: device manager, remapping, virtual output, the request server and
/// the watchers.
///
/// Runs on the main actor, and stops itself on SIGTERM and SIGINT unless a handler takes over.
@MainActor
package final class ApplicationServiceRuntime {
  /// The permission checks of the service.
  private let permissionManager: PermissionManager
  /// The router that sends controller events to the active output backend.
  private let dispatcher: VirtualOutputRouter
  /// The router that applies remapping profiles to the controllers.
  private let remappingRouter: RemappingOutputRouter
  /// The source of controllers and their sessions.
  private let manager: DeviceManager
  /// The Bluetooth LE central that connects Switch 2 controllers.
  private let bluetoothLECentral: Switch2BluetoothLECentral
  /// The server that answers the RPC and endpoint clients.
  private let applicationServiceServer: ApplicationServiceServer
  /// The remapping profiles on disk.
  private let remappingProfileLibrary: RemappingProfileLibrary
  /// The observer of system sleep and wake; nil while the runtime is stopped.
  private var systemPowerObserver: SystemPowerNotificationObserver?
  /// The watcher of the controller record files; nil while the runtime is stopped.
  private var controllerRecordWatcher: ControllerRecordWatcher?
  /// The watcher of the remapping profile files; nil while the runtime is stopped.
  private var profileWatcher: FileChangeWatcher?
  /// The watcher of the virtual device and mod package files; nil while the runtime is stopped.
  private var personaWatcher: FileChangeWatcher?
  /// The sleep and wake session of the device manager; nil while the runtime is stopped.
  private var systemPowerEventSession: DeviceManagerSystemPowerEventSession?
  /// Whether ``start()`` ran and ``stop()`` has not.
  private var started = false
  /// The signal sources of SIGTERM and SIGINT.
  private var shutdownSignalSources: [any DispatchSourceSignal] = []
  /// The handler that runs on a shutdown signal instead of stopping and exiting.
  private var shutdownSignalHandler: (@MainActor @Sendable () -> Void)?

  /// Creates the service components; nothing runs until ``start()``.
  ///
  /// - Throws: The failure to load the installation key.
  package init() throws {
    StoredDocumentMigration.run { print($0) }
    let installationKey = try PortKeyInstallationStore(directory: MacOSDataDirectory()).load()
    self.permissionManager = PermissionManager(system: MacOSAccessControlSystem())
    self.dispatcher = VirtualOutputRouter()
    let speechOutput = AVSpeechOutput()
    self.remappingProfileLibrary = RemappingProfileLibrary(speechOutput: speechOutput)
    let postEventAccess = CoreGraphicsPostEventAccess()
    let physicalOutputBridge = RemappingPhysicalOutputBridge()
    let profileSwitchBridge = RemappingProfileSwitchBridge(library: remappingProfileLibrary)
    let remappingEngine = RemappingEventEngine(
      sink: CoreGraphicsSystemInputSink(access: postEventAccess),
      gamepadSink: dispatcher,
      physicalOutputSink: physicalOutputBridge,
      profileSwitcher: profileSwitchBridge,
      systemActionPerformer: MacOSSystemActionPerformer(),
      reportSystemActionFailure: { print("System action failed: \($0.localizedDescription)") },
      speechOutput: speechOutput,
      midiOutput: CoreMIDIOutput()
    )
    self.remappingRouter = RemappingOutputRouter(
      library: remappingProfileLibrary,
      engine: remappingEngine,
      virtualOutput: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess,
      installationKey: installationKey
    )
    let bluetoothLEHub = Switch2BluetoothLEHub()
    self.manager = DeviceManager(
      dispatcher: remappingRouter,
      installationKey: installationKey,
      usbTransportProvider: OpenJoystickDriverUSBTransportProvider(),
      wirelessControllerDisconnector: BluetoothControllerDisconnector(),
      bluetoothLEHub: bluetoothLEHub,
      permissionManager: permissionManager,
      hidBackend: makeIOHIDAccessBackend
    )
    bluetoothLECentral = Switch2BluetoothLECentral(hub: bluetoothLEHub)
    physicalOutputBridge.attach(manager)
    self.applicationServiceServer = ApplicationServiceServer(
      deviceManager: manager,
      permissionManager: permissionManager,
      dispatcher: dispatcher,
      remappingProfileLibrary: remappingProfileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess,
      installationKey: installationKey,
      userSpaceDispatcherFactory: Self.makeAutomaticUserSpaceDispatcher(context:)
    )

    profileSwitchBridge.attach(applicationServiceServer)
  }

  /// Whether the request listener runs, and how to start it again; the app shows its failure.
  package var listenerState: ServiceListenerState { applicationServiceServer.listenerState }

  /// The service state that the app's Shortcuts actions read.
  package var automationService: any AutomationService { applicationServiceServer }

  /// Starts the server, the watchers, the device manager and the Bluetooth LE central.
  ///
  /// Does nothing when the runtime already started.
  ///
  /// - Throws: The failure to start the server.
  package func start() throws {
    guard !started else { return }
    started = true

    unsafe setbuf(stdout, nil)
    serviceLog("[Service] Starting main-app service runtime")
    setupGracefulShutdown()
    do { try applicationServiceServer.start() } catch {
      cancelGracefulShutdown()
      started = false
      throw error
    }
    let deviceManager = manager
    let settingsStore = SettingsStore()
    Task {
      await deviceManager.startIdleDisconnectMonitor { try? settingsStore.idleDisconnectMinutes() }
    }
    // Records apply before detection starts, so the first admission already uses them.
    let recordWatcher = ControllerRecordWatcher { changed in
      Task { await deviceManager.reloadControllerRecords(changing: changed) }
    }
    self.controllerRecordWatcher = recordWatcher
    recordWatcher.start()
    startProfileWatcher()
    startPersonaWatcher()
    let powerSession = DeviceManagerSystemPowerEventSession()
    self.systemPowerEventSession = powerSession
    let powerObserver = SystemPowerNotificationObserver { event in
      await deliverSystemPowerEvent(event, to: deviceManager, session: powerSession)
    }
    self.systemPowerObserver = powerObserver
    powerObserver.start()
    Task { await permissionManager.startPolling() }
    remappingRouter.startTicker()
    let central = bluetoothLECentral
    Task {
      await deviceManager.start()
      central.start()
      _ = await applicationServiceServer.activateVirtualOutputBackendForCurrentDevices()
    }
  }

  /// Sets the handler that runs on SIGTERM and SIGINT instead of stopping and exiting.
  ///
  /// The menu-bar host uses this so AppKit can remove the status item before the
  /// process exits. Install the handler before `start()`.
  package func handleShutdownSignal(_ handler: @escaping @MainActor @Sendable () -> Void) {
    shutdownSignalHandler = handler
  }

  /// Stops the watchers, the Bluetooth LE central, the server and the device manager, and shuts the
  /// remapping router down.
  package func stop() async {
    guard started else { return }
    started = false

    cancelGracefulShutdown()
    controllerRecordWatcher?.stop()
    controllerRecordWatcher = nil
    profileWatcher?.stop()
    profileWatcher = nil
    personaWatcher?.stop()
    personaWatcher = nil
    let observer = systemPowerObserver
    self.systemPowerObserver = nil
    let session = systemPowerEventSession
    self.systemPowerEventSession = nil
    session?.invalidate()
    bluetoothLECentral.stop()
    if let observer {
      async let observerStop: Void = observer.stop()
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

  /// Reloads profiles when their files change.
  private func startProfileWatcher() {
    let library = remappingProfileLibrary
    let targets = Self.profileWatchTargets(for: library)
    for directory in targets.directories {
      do { try RemappingProfileLibrary.createPrivateDirectory(directory) } catch {
        serviceError("[Profiles] Cannot create \(directory.path): \(error.localizedDescription)")
      }
    }
    let server = applicationServiceServer
    let watcher = FileChangeWatcher(
      directories: targets.directories,
      watchesFile: targets.watchesFile
    ) { Task { await server.reloadRemappingProfiles() } }
    self.profileWatcher = watcher
    watcher.start()
  }

  /// What the profile watcher watches: the library folder for its selections file, `Profiles/`
  /// for each profile file, and `Packages/`, where installing, replacing, or removing a mod
  /// package renames or deletes the package's folder.
  static func profileWatchTargets(
    for library: RemappingProfileLibrary
  ) -> (directories: [URL], watchesFile: (URL) -> Bool) {
    let selectionsURL = library.selectionsURL.standardizedFileURL
    let profilesDirectory = library.profilesDirectory.standardizedFileURL
    let packagesDirectory = library.packagesDirectory.standardizedFileURL
    return (
      [library.directory, library.profilesDirectory, library.packagesDirectory],
      { url in
        let parent = url.deletingLastPathComponent().standardizedFileURL
        return url.standardizedFileURL == selectionsURL || parent == profilesDirectory
          || parent == packagesDirectory
      }
    )
  }

  /// Re-creates a connected controller's virtual device when a change to the virtual device files
  /// changes its identity.
  ///
  /// The service creates the VirtualDevices and package folders, which are absent until first use;
  /// a folder removed later is watched once it exists again.
  private func startPersonaWatcher() {
    let server = applicationServiceServer
    let packages = ModPackageStore.rootDirectory
    for folder in [VirtualHIDProfileOverrideStore.userDirectory, packages] {
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch {
        serviceError("[VirtualDevices] Cannot create \(folder.path): \(error.localizedDescription)")
      }
    }
    let watcher = FileChangeWatcher(
      directories: [VirtualHIDProfileOverrideStore.userDirectory, packages],
      watchesFile: {
        $0.pathExtension == "plist"
          || $0.deletingLastPathComponent().standardizedFileURL == packages.standardizedFileURL
      },
      onChange: { Task { await server.reloadPersonas() } }
    )
    self.personaWatcher = watcher
    watcher.start()
  }

  /// Prints `message`.
  private func serviceLog(_ message: String) { print(message) }

  /// Prints `message` to standard error.
  private func serviceError(_ message: String) { unsafe fputs("\(message)\n", unsafe stderr) }

  /// Installs the handlers of SIGTERM and SIGINT.
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

  /// Cancels the handlers of SIGTERM and SIGINT.
  private func cancelGracefulShutdown() {
    let sources = shutdownSignalSources
    shutdownSignalSources.removeAll()
    for source in sources { source.cancel() }
  }
}

/// Delivers a sleep or wake event to the device manager and returns when it has been handled.
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
/// controllers.
///
/// The revoked runtime session rejects late actor entry; `DeviceManager.stop()` clears the sleep
/// state of a power operation that entered before invalidation.
private final class RuntimePowerEventCompletion: Sendable {
  /// The continuation and whether the delivery finished.
  private let state = Locked<(continuation: CheckedContinuation<Void, Never>?, isFinished: Bool)>(
    (nil, false)
  )

  /// Stores `continuation`, or resumes it at once when the delivery already finished.
  func install(_ continuation: CheckedContinuation<Void, Never>) {
    let isFinished = state.withLock { state in
      if !state.isFinished { state.continuation = continuation }
      return state.isFinished
    }
    if isFinished { continuation.resume() }
  }

  /// Marks the delivery finished and resumes the continuation.
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
