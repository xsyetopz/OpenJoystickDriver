import AppKit
import Foundation
import OpenJoystickDriverKit

let appModelPollNanoseconds: UInt64 = 2_000_000_000
let serviceHealthPollNanosecondsConnected: UInt64 = 15_000_000_000
let serviceHealthPollNanosecondsDisconnected: UInt64 = 2_000_000_000
let includePrereleaseUpdatesDefaultsKey = "IncludePrereleaseUpdates"

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
  let physicalOutputCapabilities: PhysicalControllerOutputCapabilities

  init(from description: ApplicationServiceDeviceDescription) {
    self.id = "\(description.vendorID):\(description.productID):\(description.name)"
    self.name = description.name
    self.vendorID = description.vendorID
    self.productID = description.productID
    self.parser = description.parser
    self.connection = description.connection
    self.serialNumber = description.serialNumber
    self.supportsPhysicalRumble = description.supportsPhysicalRumble
    self.physicalOutputCapabilities = description.physicalOutputCapabilities
  }
}

/// Central observable model for GUI.
///
/// Polls the in-process runtime through bounded local RPC every 2 seconds.
@MainActor final class AppModel: ObservableObject {
  enum ApplicationServiceUIState: Equatable, Sendable {
    case missing
    case stopped
    case runningConnected
    case runningDisconnected
    case restarting
    case crashLooping
    case unknown
  }

  @Published var serviceConnected = false
  @Published var serviceInstalled = false
  @Published var serviceRestarting = false
  @Published var serviceError: String?
  @Published var serviceHealth: ApplicationServiceManager.ApplicationServiceHealth?
  @Published var devices: [DeviceViewModel] = []
  @Published var inputMonitoring = "unknown"
  @Published var accessibility = "unknown"
  @Published var inputMonitoringAssist: String?
  @Published var extensionManager = SystemExtensionLifecycle()

  var inputMonitoringState: PermissionManager.AccessState {
    PermissionManager.AccessState(status: inputMonitoring)
  }

  var accessibilityState: PermissionManager.AccessState {
    PermissionManager.AccessState(status: accessibility)
  }

  var permissionsReady: Bool { inputMonitoringState == .granted && accessibilityState == .granted }

  @Published var userSpaceVirtualDeviceEnabled = false
  @Published var userSpaceVirtualDeviceStatus = "unknown"
  @Published var compatibilityIdentity: String = CompatibilityIdentity.sdl2_3.rawValue
  @Published var virtualDeviceDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?
  @Published var virtualDeviceSelfTest: ApplicationServiceVirtualDeviceSelfTestPayload?
  @Published var creatingSupportReport = false
  var latestStatusPayload: ApplicationServiceStatusPayload?
  @Published var updateCheckState: UpdateCheckState = .idle
  @Published var includePrereleaseUpdates: Bool {
    didSet {
      updateCheckState = .idle
      UserDefaults.standard.set(
        includePrereleaseUpdates,
        forKey: includePrereleaseUpdatesDefaultsKey
      )
    }
  }

  var developerMode: Bool

  var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.5.0-alpha.5"
  }

  let client = ApplicationServiceClient()
  let permissionManager = PermissionManager()
  let updateChecker = UpdateChecker()
  lazy var sparkleUpdates = SparkleUpdateController { [weak self] state in
    self?.updateCheckState = state
  }
  var pollTask: Task<Void, Never>?

  var lastHealthPollNs: UInt64 = 0

  // Tracks observed runtime PID changes so the UI can distinguish a stopped app from
  // repeated relaunches.
  var lastServicePID: Int?
  var serviceStartEventsNanoseconds: [UInt64] = []

  init(developerMode: Bool = false) {
    self.developerMode = developerMode
    self.includePrereleaseUpdates = UserDefaults.standard.bool(
      forKey: includePrereleaseUpdatesDefaultsKey
    )
  }

  var applicationServiceUIState: ApplicationServiceUIState {
    if serviceRestarting { return .restarting }
    if serviceConnected { return .runningConnected }
    guard serviceInstalled else { return .missing }
    guard let h = serviceHealth, h.installed else {
      return serviceConnected ? .runningConnected : .unknown
    }

    if recentServiceStartCount(windowSeconds: 10) >= 3 { return .crashLooping }
    if recentServiceStartCount(windowSeconds: 4) > 0 && !serviceConnected { return .restarting }

    if serviceConnected { return .runningConnected }
    if h.pid != nil { return .runningDisconnected }
    if (h.state ?? "").uppercased() == "NOT_LOADED" { return .stopped }
    return .unknown
  }

  var applicationServiceStatusLabel: String {
    switch applicationServiceUIState {
    case .missing: return L10n.string("service.status.missing")
    case .stopped: return L10n.string("service.status.stopped")
    case .runningConnected: return L10n.string("service.status.running")
    case .runningDisconnected: return L10n.string("service.status.runningDisconnected")
    case .restarting: return L10n.string("service.status.restarting")
    case .crashLooping: return L10n.string("service.status.crashLooping")
    case .unknown:
      return serviceConnected
        ? L10n.string("service.status.running") : L10n.string("service.status.unknown")
    }
  }

  var applicationServiceSuggestedActionLabel: String? {
    switch applicationServiceUIState {
    case .missing: return L10n.string("button.installService")
    case .stopped: return L10n.string("button.startService")
    case .runningDisconnected, .restarting, .crashLooping:
      return L10n.string("button.restartService")
    case .runningConnected, .unknown: return nil
    }
  }

  func start() async {
    refreshApplicationServiceStatus()
    await registerMainAppForLoginIfNeeded()
    refreshApplicationServiceStatus()
    await refreshApplicationServiceHealth()
    client.connect()
    await poll()
    await refreshVirtualDeviceDiagnostics()
    extensionManager.refreshInstallState()
    if !sparkleUpdates.isConfigured { Task { await checkForUpdates() } }
  }

  func setPollingEnabled(_ enabled: Bool) {
    if enabled {
      guard pollTask == nil else { return }
      startPolling()
      return
    }

    pollTask?.cancel()
    pollTask = nil
    client.disconnect()
  }

  func refreshApplicationServiceStatus() {
    serviceInstalled = ApplicationServiceManager.isInstalled
  }

  func refreshApplicationServiceHealth() async {
    let snapshot = await Task.detached { ApplicationServiceManager.health() }.value
    serviceHealth = snapshot
    noteApplicationServiceHealth(snapshot)
    lastHealthPollNs = DispatchTime.now().uptimeNanoseconds
  }

  /// One-shot refresh used after lifecycle actions (install/start/restart/uninstall).
  ///
  /// This avoids relying on the 2s poll interval to correct UI state.
  func syncFromApplicationServiceNow() async {
    refreshApplicationServiceStatus()
    await refreshApplicationServiceHealth()
    await poll()
    await refreshVirtualDeviceDiagnostics()
  }

  func registerMainAppForLoginIfNeeded() async {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    do {
      let task = Task.detached { try ApplicationServiceManager.installByDefaultIfNeeded() }
      try await task.value
    } catch { serviceError = formatApplicationServiceError(error) }
  }

}
