import AppKit
import Foundation
import OpenJoystickDriverKit

let appModelPollNanoseconds: UInt64 = 2_000_000_000
let daemonHealthPollNanosecondsConnected: UInt64 = 15_000_000_000
let daemonHealthPollNanosecondsDisconnected: UInt64 = 2_000_000_000
let inputMonitoringPromptPollNanoseconds: UInt64 = 500_000_000
let inputMonitoringPromptPollAttempts = 240
let includePrereleaseUpdatesDefaultsKey = "IncludePrereleaseUpdates"
let daemonRepairBundleVersionDefaultsKey = "DaemonRepairBundleVersion"

/// Parsed, displayable representation of connected controller.
struct DeviceViewModel: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let vendorID: UInt16
  let productID: UInt16
  let parser: String
  /// "USB" or "HID".
  let connection: String
  /// USB serial number string, nil when unavailable.
  let serialNumber: String?
  let supportsPhysicalRumble: Bool

  init(from description: XPCDeviceDescription) {
    self.id = "\(description.vendorID):\(description.productID):\(description.name)"
    self.name = description.name
    self.vendorID = description.vendorID
    self.productID = description.productID
    self.parser = description.parser
    self.connection = description.connection
    self.serialNumber = description.serialNumber
    self.supportsPhysicalRumble = description.supportsPhysicalRumble
  }
}

/// Central observable model for GUI.
///
/// Polls daemon via XPC every 2 seconds.
@MainActor final class AppModel: ObservableObject {
  enum DaemonUIState: Equatable, Sendable {
    case missing
    case stopped
    case runningConnected
    case runningDisconnected
    case restarting
    case crashLooping
    case unknown
  }

  @Published var daemonConnected = false
  @Published var daemonInstalled = false
  @Published var daemonRestarting = false
  @Published var daemonError: String?
  @Published var daemonHealth: DaemonManager.DaemonHealth?
  @Published var devices: [DeviceViewModel] = []
  @Published var appInputMonitoring = "unknown"
  @Published var inputMonitoring = "unknown"
  @Published var inputMonitoringAssist: String?
  @Published var extensionManager = SystemExtensionManager()

  @Published var userSpaceVirtualDeviceEnabled = false
  @Published var userSpaceVirtualDeviceStatus = "unknown"
  @Published var virtualDeviceMode: String = VirtualDeviceMode.compatUserSpace.rawValue
  @Published var outputMode: String = CompositeOutputDispatcher.Mode.primaryOnly.rawValue
  @Published var compatibilityIdentity: String = CompatibilityIdentity.sdl2_3.rawValue
  @Published var virtualDeviceDiagnostics: XPCVirtualDeviceDiagnosticsPayload?
  @Published var virtualDeviceSelfTest: XPCVirtualDeviceSelfTestPayload?
  @Published var updateCheckState: UpdateCheckState = .idle
  @Published var includePrereleaseUpdates: Bool {
    didSet {
      UserDefaults.standard.set(
        includePrereleaseUpdates,
        forKey: includePrereleaseUpdatesDefaultsKey
      )
    }
  }

  var developerMode: Bool

  var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.5.0-alpha.6"
  }

  let client = XPCClient()
  let permissionManager = PermissionManager()
  let updateChecker = UpdateChecker()
  let compatibilityOutputBridge = AppOwnedCompatibilityOutputBridge()
  lazy var sparkleUpdates = SparkleUpdateController { [weak self] state in
    self?.updateCheckState = state
  }
  var pollTask: Task<Void, Never>?
  var compatibilityOutputTask: Task<Void, Never>?

  var lastHealthPollNs: UInt64 = 0

  // Tracks recent launchd restarts (based on `launchctl print runs = ...`) so the UI can
  // distinguish "stopped" from "restarting" and "crash-looping".
  var lastDaemonRuns: Int?
  var lastDaemonPid: Int?
  var daemonStartEventsNs: [UInt64] = []

  init(developerMode: Bool = false) {
    self.developerMode = developerMode
    self.includePrereleaseUpdates = UserDefaults.standard.bool(
      forKey: includePrereleaseUpdatesDefaultsKey
    )
  }

  var daemonUIState: DaemonUIState {
    if daemonRestarting { return .restarting }
    guard daemonInstalled else { return .missing }
    guard let h = daemonHealth, h.installed else {
      return daemonConnected ? .runningConnected : .unknown
    }

    if h.isInefficientKillLoop { return .crashLooping }
    if recentDaemonStartCount(windowSeconds: 10) >= 3 { return .crashLooping }
    if recentDaemonStartCount(windowSeconds: 4) > 0 && !daemonConnected { return .restarting }

    if daemonConnected { return .runningConnected }
    if h.pid != nil { return .runningDisconnected }
    if (h.state ?? "").uppercased() == "NOT_LOADED" { return .stopped }
    return .unknown
  }

  var daemonStatusLabel: String {
    switch daemonUIState {
    case .missing: return L10n.string("daemon.status.missing")
    case .stopped: return L10n.string("daemon.status.stopped")
    case .runningConnected: return L10n.string("daemon.status.running")
    case .runningDisconnected: return L10n.string("daemon.status.runningDisconnected")
    case .restarting: return L10n.string("daemon.status.restarting")
    case .crashLooping: return L10n.string("daemon.status.crashLooping")
    case .unknown:
      return daemonConnected
        ? L10n.string("daemon.status.running")
        : L10n.string("daemon.status.unknown")
    }
  }

  var daemonSuggestedActionLabel: String? {
    switch daemonUIState {
    case .missing: return L10n.string("button.installDaemon")
    case .stopped: return L10n.string("button.startDaemon")
    case .runningDisconnected, .restarting, .crashLooping:
      return L10n.string("button.restartDaemon")
    case .runningConnected, .unknown: return nil
    }
  }

  func start() async {
    refreshDaemonStatus()
    await repairDaemonForCurrentAppVersionIfNeeded()
    refreshDaemonStatus()
    await refreshDaemonHealth()
    if daemonInstalled { client.connect() }
    await poll()
    await refreshVirtualDeviceDiagnostics()
    extensionManager.refreshInstallState()
    if !sparkleUpdates.isConfigured {
      Task { await checkForUpdates() }
    }
  }

  func setPollingEnabled(_ enabled: Bool) {
    if enabled {
      guard pollTask == nil else { return }
      startPolling()
      return
    }

    pollTask?.cancel()
    pollTask = nil
    compatibilityOutputTask?.cancel()
    compatibilityOutputTask = nil
    compatibilityOutputBridge.stop()
    client.disconnect()
  }

  func refreshDaemonStatus() { daemonInstalled = DaemonManager.isInstalled }

  func refreshDaemonHealth() async {
    let snapshot = await Task.detached { DaemonManager.health() }.value
    daemonHealth = snapshot
    noteDaemonHealth(snapshot)
    lastHealthPollNs = DispatchTime.now().uptimeNanoseconds
  }

  /// One-shot refresh used after lifecycle actions (install/start/restart/uninstall).
  ///
  /// This avoids relying on the 2s poll interval to correct UI state.
  func syncFromDaemonNow() async {
    refreshDaemonStatus()
    await refreshDaemonHealth()
    await poll()
    await refreshVirtualDeviceDiagnostics()
  }

  func repairDaemonForCurrentAppVersionIfNeeded() async {
    guard daemonInstalled, Bundle.main.bundleURL.pathExtension == "app" else { return }
    let currentBundleVersion =
      Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? appVersion
    guard !currentBundleVersion.isEmpty else { return }
    guard UserDefaults.standard.string(forKey: daemonRepairBundleVersionDefaultsKey)
      != currentBundleVersion
    else {
      return
    }

    do {
      let task = Task.detached { try DaemonManager.restart() }
      try await task.value
      UserDefaults.standard.set(currentBundleVersion, forKey: daemonRepairBundleVersionDefaultsKey)
    } catch {
      daemonError = formatDaemonError(error)
    }
  }

}
