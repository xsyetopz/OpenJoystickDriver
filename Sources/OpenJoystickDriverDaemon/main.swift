import AppKit
import Foundation
import OpenJoystickDriverKit

// Disable stdout buffering so log lines appear immediately in StandardOutPath file.
setbuf(stdout, nil)

let permissionManager = PermissionManager()
let commandLineArguments = Set(CommandLine.arguments.dropFirst())

func daemonLog(_ message: String) {
  print(message)
  NSLog("%@", message)
}

@MainActor
final class PermissionPromptAppDelegate: NSObject, NSApplicationDelegate {
  private let permissionManager: PermissionManager
  private var pollTask: Task<Void, Never>?

  init(permissionManager: PermissionManager) {
    self.permissionManager = permissionManager
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    daemonLog("[Daemon] Requesting Input Monitoring access for daemon...")

    pollTask = Task { @MainActor [permissionManager] in
      let initialState = await permissionManager.requestAccess()
      if initialState == .granted {
        daemonLog("[Daemon] Input Monitoring granted for daemon helper app")
        NSApp.terminate(nil)
        return
      }
      if initialState == .denied {
        daemonLog("[Daemon] Input Monitoring denied for daemon helper app")
        NSApp.terminate(nil)
        return
      }

      let timeoutNanoseconds: UInt64 = 120_000_000_000
      let pollNanoseconds: UInt64 = 500_000_000
      let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

      while !Task.isCancelled {
        let state = await permissionManager.checkAccess()
        if state == .granted {
          daemonLog("[Daemon] Input Monitoring granted for daemon helper app")
          NSApp.terminate(nil)
          return
        }
        if state == .denied {
          daemonLog("[Daemon] Input Monitoring denied for daemon helper app")
          NSApp.terminate(nil)
          return
        }
        if DispatchTime.now().uptimeNanoseconds >= deadline {
          daemonLog("[Daemon] Input Monitoring helper timed out waiting for approval")
          NSApp.terminate(nil)
          return
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    pollTask?.cancel()
    pollTask = nil
  }
}

if let probeArgument = commandLineArguments.first(where: {
  $0.hasPrefix("--probe-foreground-consumer-memory=")
}) {
  let rawIterations = String(
    probeArgument.dropFirst("--probe-foreground-consumer-memory=".count)
  )
  guard let iterations = Int(rawIterations), (1...100_000).contains(iterations) else {
    daemonLog("[Daemon] Probe iterations must be 1...100000")
    exit(1)
  }
  do {
    let result = try ForegroundConsumerMemoryProbe.run(iterations: iterations)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    print(String(data: data, encoding: .utf8) ?? "{}")
    exit(0)
  } catch {
    daemonLog("[Daemon] Foreground consumer memory probe failed: \(error.localizedDescription)")
    exit(1)
  }
}

let environment = ProcessInfo.processInfo.environment
let permissionCheckOnlyMode = environment["OJD_PERMISSION_CHECK_ONLY"] == "1"
let promptOnlyMode = environment["OJD_PERMISSION_PROMPT_ONLY"] == "1"
  || commandLineArguments.contains("--request-input-monitoring")

if permissionCheckOnlyMode {
  daemonLog("[Daemon] Starting permission-check probe mode")
  print(PermissionManager.currentAccessState())
  exit(0)
}

if promptOnlyMode {
  daemonLog("[Daemon] Starting permission prompt helper mode")
  let appDelegate = PermissionPromptAppDelegate(permissionManager: permissionManager)
  NSApplication.shared.delegate = appDelegate
  _ = appDelegate
  NSApplication.shared.run()
  exit(0)
}

// DriverKit virtual HID output is optional and can be enabled/disabled by the GUI via XPC.
// We do not connect eagerly at startup — this avoids "half-active" states where the
// DriverKit virtual device is present but idle while Compatibility is selected.
let dextDispatcher = DextOutputDispatcher()
daemonLog("[Daemon] DriverKit output: on-demand (managed by Mode)")
daemonLog("[Daemon] Starting daemon service mode")

// Optional secondary output is controlled by the GUI via XPC (user-space IOHIDUserDevice).
let dispatcher = CompositeOutputDispatcher(primary: dextDispatcher)

let manager = DeviceManager(dispatcher: dispatcher)
let xpcService = XPCService(
  deviceManager: manager,
  permissionManager: permissionManager,
  dispatcher: dispatcher,
  dextDispatcher: dextDispatcher
)
let foregroundConsumerOutputMonitor = ForegroundConsumerOutputMonitor(
  deviceManager: manager
) {
  frontmostBundleRootPath,
  effectiveConsumerBundleRoots,
  observedConsumerBundleRoots,
  activeRouteToken in
  await xpcService.applyForegroundCompatibilityRoutingUpdate(
    frontmostBundleRootPath: frontmostBundleRootPath,
    effectiveConsumerBundleRoots: effectiveConsumerBundleRoots,
    observedConsumerBundleRoots: observedConsumerBundleRoots,
    activeRouteToken: activeRouteToken
  )
}

manager.setupGracefulShutdown(label: "Daemon")

daemonLog("[Daemon] OpenJoystickDriverDaemon starting...")

Task { await permissionManager.startPolling() }

xpcService.start()
foregroundConsumerOutputMonitor.start()

Task { await manager.start() }

// Keep process alive (also services IOKit RunLoop)
RunLoop.main.run()
