import AppKit
import OpenJoystickDriverKit
import SwiftUI

struct MenuBarPopoverView: View {
  @EnvironmentObject var model: AppModel
  @State private var runningSelfTest = false
  @State private var showUninstallConfirm = false
  @State private var showAdvanced = false
  @State private var inputTester = InputTestWindowController()

  private var gameControllerSupportLabel: String {
    guard let devices = model.virtualDeviceDiagnostics?.hidGamepads else {
      return "unknown"
    }
    let ojdDevices = devices.filter { $0.isOJDUserSpace || $0.isOJDDriverKit }
    if ojdDevices.isEmpty { return "no OJD virtual device visible" }
    if ojdDevices.contains(where: { $0.isGameControllerSupported == true }) {
      return "yes"
    }
    if ojdDevices.contains(where: { $0.isGameControllerSupported == nil }) {
      return "unknown on this macOS version"
    }
    return "no"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        headerRow
        readinessCard
        permissionsCard
        gameProfileCard
        inputTestRow
        advancedToggle
        if showAdvanced {
          outputDetailsCard
          helperCard
          selfTestRow
          updateRow
          footerRow
        }
      }
      .padding(14)
    }
    .frame(width: 440)
    .alert(isPresented: $showUninstallConfirm) {
      Alert(
        title: Text("Uninstall LaunchAgent?"),
        message: Text("This removes the LaunchAgent plist. You can reinstall later."),
        primaryButton: .destructive(Text("Uninstall")) {
          Task {
            await model.uninstallDaemon()
            await model.syncFromDaemonNow()
          }
        },
        secondaryButton: .cancel()
      )
    }
  }

  private var headerRow: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("OpenJoystickDriver")
          .font(.system(size: 17, weight: .semibold))
      }
      Spacer()
      SwiftUI.Button("Quit") { NSApplication.shared.terminate(nil) }
        .buttonStyle(.borderless)
        .foregroundColor(.secondary)
    }
  }

  private var readinessCard: some View {
    let permissionsReady =
      model.appInputMonitoring == "granted" && model.inputMonitoring == "granted"
    let ready = model.daemonConnected && permissionsReady
    let title = ready ? "Ready" : "Setup needs attention"
    let summary: String = {
      switch model.daemonUIState {
      case .restarting:
        return "The helper is restarting."
      case .crashLooping:
        return "The helper is crash-looping. Restart or reinstall it."
      case .missing:
        return "Install the helper to read controller input."
      case .stopped:
        return "Start the helper to connect controllers."
      case .runningDisconnected:
        return "The helper is running but disconnected. Restart the helper."
      case .runningConnected, .unknown:
        break
      }
      if !model.daemonInstalled { return "Install the helper to read controller input." }
      if !model.daemonConnected { return "Start the helper to connect controllers." }
      if model.appInputMonitoring != "granted" {
        return "Allow Input Monitoring for OpenJoystickDriver."
      }
      if model.inputMonitoring != "granted" {
        return "Allow Input Monitoring for OpenJoystickDriver Helper."
      }
      if model.devices.isEmpty { return "Connect a controller." }
      return "\(model.devices.count) controller\(model.devices.count == 1 ? "" : "s") connected."
    }()

    return OJDCard {
      HStack(alignment: .top, spacing: 12) {
        StatusOrb(isReady: ready, isBusy: model.daemonRestarting)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
          Text(summary)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Text(model.daemonStatusLabel)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .foregroundColor(ready ? .green : .secondary)
          .background(Capsule().fill(Color.secondary.opacity(0.12)))
      }

      HStack(spacing: 10) {
        MetricChip(title: "Controllers", value: "\(model.devices.count)")
        MetricChip(title: "Profile", value: compatibilityIdentityLabel)
        MetricChip(title: "Access", value: permissionsReady ? "Allowed" : "Needs access")
      }
      .padding(.top, 4)

      if !ready {
        readinessAction
      }

      if let err = model.daemonError {
        Text(err)
          .font(.caption)
          .foregroundColor(.red)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 2)
      }
    }
  }

  @ViewBuilder
  private var readinessAction: some View {
    if model.daemonRestarting {
      EmptyView()
    } else if model.appInputMonitoring != "granted" {
      SwiftUI.Button("Request Access") {
        Task { await model.requestAppInputMonitoringAccess() }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if model.inputMonitoring != "granted" {
      SwiftUI.Button("Request Access") {
        Task { await model.requestDaemonInputMonitoringAccess() }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if !model.daemonInstalled {
      SwiftUI.Button("Install Helper") {
        Task {
          await model.installDaemon()
          await model.syncFromDaemonNow()
        }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if !model.daemonConnected {
      if model.daemonUIState == .stopped || model.daemonUIState == .unknown {
        SwiftUI.Button("Start Helper") {
          Task {
            await model.startDaemon()
            await model.syncFromDaemonNow()
          }
        }
        .controlSize(.small)
        .padding(.top, 2)
      } else {
        SwiftUI.Button("Restart Helper") {
          Task {
            await model.restartDaemon()
            await model.syncFromDaemonNow()
          }
        }
        .controlSize(.small)
        .padding(.top, 2)
      }
    }
  }

  private var helperCard: some View {
    OJDCard(title: "Helper") {
      VStack(alignment: .leading, spacing: 10) {
        if let h = model.daemonHealth, h.installed {
          let state = h.state ?? "unknown"
          let pid = h.pid.map { "\($0)" } ?? "?"
          let runs = h.runs.map { "\($0)" } ?? "?"
          let reason = h.isInefficientKillLoop ? (h.immediateReason ?? h.blame) : nil
          HStack(spacing: 8) {
            Text("launchd \(state), pid \(pid), runs \(runs)\(reason.map { ", \($0)" } ?? "")")
              .font(.caption)
              .foregroundColor(h.isInefficientKillLoop ? .orange : .secondary)
              .lineLimit(2)
            Spacer()
            SwiftUI.Button("Refresh") {
              Task { await model.refreshDaemonHealth() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
          }
        } else {
          Text("The helper starts automatically after install.")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Divider()

        HStack(spacing: 8) {
          Text("System extension")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Text(model.extensionManager.installState.label)
            .font(.caption.weight(.semibold))
            .foregroundColor(model.extensionManager.installState.isInstalled ? .green : .secondary)
          SwiftUI.Button("Install") { model.extensionManager.installExtension() }
            .controlSize(.small)
            .disabled(
              model.extensionManager.installState.isInstalled ||
                model.extensionManager.installState.isPending
            )
        }
        if case .failed(let msg) = model.extensionManager.installState {
          Text(msg)
            .font(.caption)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let warning = model.extensionManager.installWarning,
          model.extensionManager.installState.isInstalled
        {
          Text(warning)
            .font(.caption)
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 8) {
          if !model.daemonInstalled {
            SwiftUI.Button("Install Helper") {
              Task {
                await model.installDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
          } else {
            SwiftUI.Button("Start") {
              Task {
                await model.startDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
            .disabled(
              model.daemonUIState == .runningConnected
                || model.daemonUIState == .runningDisconnected
                || model.daemonUIState == .restarting
                || model.daemonUIState == .crashLooping
            )
            SwiftUI.Button("Restart") {
              Task {
                await model.restartDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
            .disabled(model.daemonRestarting)
            SwiftUI.Button("Uninstall") { showUninstallConfirm = true }
              .buttonStyle(.borderless)
              .controlSize(.small)
              .foregroundColor(.secondary)
              .disabled(model.daemonRestarting)
          }
        }
      }
    }
  }

  private var permissionsCard: some View {
    OJDCard(title: "Permissions") {
      VStack(alignment: .leading, spacing: 8) {
        PermissionRow(
          title: "OpenJoystickDriver",
          subtitle: permissionSubtitle(for: model.appInputMonitoring, owner: "the app"),
          state: model.appInputMonitoring,
          actionTitle: permissionActionTitle(for: model.appInputMonitoring)
        ) {
          Task { await model.requestAppInputMonitoringAccess() }
        }
        Divider()
        PermissionRow(
          title: "OpenJoystickDriver Helper",
          subtitle: permissionSubtitle(
            for: model.inputMonitoring,
            owner: "the helper",
            settingsName: "OpenJoystickDriver Helper"
          ),
          state: model.inputMonitoring,
          actionTitle: permissionActionTitle(for: model.inputMonitoring),
          disabled: model.daemonRestarting
        ) {
          Task { await model.requestDaemonInputMonitoringAccess() }
        }
        if let assist = model.inputMonitoringAssist {
          PermissionAssistView(message: assist)
        }
      }
    }
  }

  private func permissionActionTitle(for state: String) -> String {
    state == "granted" ? "Allowed" : "Request Access"
  }

  private func permissionSubtitle(
    for state: String,
    owner: String,
    settingsName: String? = nil
  ) -> String {
    switch state {
    case "granted":
      return "Access is allowed."
    case "denied":
      let name = settingsName ?? owner
      return "Open System Settings, then turn on Input Monitoring for \(name)."
    default:
      return "Request access so macOS can add this item to Input Monitoring."
    }
  }

  private var gameProfileCard: some View {
    OJDCard(title: "Game profile") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Compatibility mode works well for Steam, emulators, and SDL-based apps.")
              .font(.caption)
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          if model.virtualDeviceMode != VirtualDeviceMode.compatUserSpace.rawValue {
            SwiftUI.Button("Use Compatibility") {
              Task { await model.setVirtualDeviceMode(VirtualDeviceMode.compatUserSpace.rawValue) }
            }
            .controlSize(.small)
            .disabled(!model.daemonConnected)
          }
        }

        let compatSelected = model.virtualDeviceMode == VirtualDeviceMode.compatUserSpace.rawValue
        HStack(spacing: 10) {
          Text("Identity")
            .font(.caption)
            .foregroundColor(.secondary)
          Picker(
            "Compatibility identity",
            selection: Binding(
              get: { model.compatibilityIdentity },
              set: { v in Task { await model.setCompatibilityIdentity(v) } }
            )
          ) {
            Text("SDL 2/3").tag(CompatibilityIdentity.sdl2_3.rawValue)
            Text("Apple GameController").tag(CompatibilityIdentity.appleGameController.rawValue)
            Text("Generic HID").tag(CompatibilityIdentity.genericHID.rawValue)
            Text("Xbox 360 HID").tag(CompatibilityIdentity.x360HID.rawValue)
            Text("Xbox One HID").tag(CompatibilityIdentity.xoneHID.rawValue)
          }
          .frame(maxWidth: .infinity)
          .disabled(!model.daemonConnected || !compatSelected)
        }

        if !compatSelected {
          Text("Switch to Compatibility mode before changing profiles.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  private var outputDetailsCard: some View {
    OJDCard(title: "Output details") {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          "Mode",
          selection: Binding(
            get: { model.virtualDeviceMode },
            set: { newValue in Task { await model.setVirtualDeviceMode(newValue) } }
          )
        ) {
          Text("Auto").tag(VirtualDeviceMode.auto.rawValue)
          Text("DriverKit").tag(VirtualDeviceMode.driverKit.rawValue)
          Text("Compatibility").tag(VirtualDeviceMode.compatUserSpace.rawValue)
          if model.developerMode {
            Text("Both").tag(VirtualDeviceMode.both.rawValue)
          }
        }
        .pickerStyle(.segmented)
        .disabled(!model.daemonConnected)

        VStack(alignment: .leading, spacing: 3) {
          statusLine("Active", activeOutputLabel)
          statusLine(
            "Backend",
            model.userSpaceVirtualDeviceStatus,
            warning: model.userSpaceVirtualDeviceStatus.hasPrefix("error:")
          )
          statusLine(
            "GameController",
            gameControllerSupportLabel,
            success: gameControllerSupportLabel == "yes"
          )
          if let s = model.virtualDeviceDiagnostics?.driverKitOutputStats {
            statusLine(
              "DriverKit reports",
              "ok \(s.successes), fail \(s.failures), last \(s.lastErrorHex ?? "none")"
            )
          }
        }
      }
    }
  }

  private func statusLine(
    _ label: String,
    _ value: String,
    success: Bool = false,
    warning: Bool = false
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 96, alignment: .leading)
      Text(value)
        .font(.caption)
        .foregroundColor(success ? .green : (warning ? .orange : .secondary))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var activeOutputLabel: String {
    switch model.outputMode {
    case CompositeOutputDispatcher.Mode.primaryOnly.rawValue: return "DriverKit"
    case CompositeOutputDispatcher.Mode.secondaryOnly.rawValue: return "Compatibility"
    case CompositeOutputDispatcher.Mode.both.rawValue: return "Both"
    default: return "Unknown"
    }
  }

  private var compatibilityIdentityLabel: String {
    switch model.compatibilityIdentity {
    case CompatibilityIdentity.sdl2_3.rawValue: return "SDL"
    case CompatibilityIdentity.appleGameController.rawValue: return "GameController"
    case CompatibilityIdentity.genericHID.rawValue: return "Generic HID"
    case CompatibilityIdentity.x360HID.rawValue: return "Xbox 360"
    case CompatibilityIdentity.xoneHID.rawValue: return "Xbox One"
    default: return model.compatibilityIdentity
    }
  }

  private var selfTestRow: some View {
    OJDCard(title: "Self-test") {
      VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Check virtual output for 5 seconds.")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        SwiftUI.Button(runningSelfTest ? "Running…" : "Run 5s") {
          runningSelfTest = true
          Task {
              await model.syncFromDaemonNow()
            if model.daemonHealth?.isInefficientKillLoop == true {
              model.daemonError =
                "Daemon is being killed by launchd (inefficient). " +
                "Fix daemon stability before self-test."
              runningSelfTest = false
              return
            }
            await model.runVirtualDeviceSelfTest(seconds: 5)
            runningSelfTest = false
          }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!model.daemonConnected || runningSelfTest)
      }
      if let t = model.virtualDeviceSelfTest {
        VStack(alignment: .leading, spacing: 3) {
          statusLine(
            "DriverKit",
            "value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)"
          )
          if let delta = t.driverKitInputReportDelta {
            statusLine("ioreg input", "Δ \(delta)")
          }
          if let delta = t.driverKitSetReportSuccessDelta {
            statusLine("daemon setReport", "ok Δ \(delta)")
          }
          statusLine(
            "User-space",
            "value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)"
          )
        }
      } else {
        Text("Press controller buttons during the check.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      }
    }
  }

  private var inputTestRow: some View {
    OJDCard(title: "Input Test") {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("View live buttons, sticks, packets, and rumble controls.")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          SwiftUI.Button("Open Input Test") {
            inputTester.show(model: model)
          }
          .controlSize(.small)
          .disabled(!model.daemonConnected)
        }
      }
    }
  }

  private var advancedToggle: some View {
    SwiftUI.Button {
      showAdvanced.toggle()
    } label: {
      HStack {
        Text(showAdvanced ? "Hide details" : "Show details")
        Spacer()
        Text(showAdvanced ? "▴" : "▾")
      }
      .font(.caption.weight(.semibold))
      .foregroundColor(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.secondary.opacity(0.08))
      )
    }
    .buttonStyle(.plain)
  }

  private var footerRow: some View {
    HStack(spacing: 10) {
      SwiftUI.Button("Refresh") {
        Task {
          await model.syncFromDaemonNow()
        }
      }
      .buttonStyle(.borderless)

      SwiftUI.Button("Show Log") {
        NSWorkspace.shared.selectFile(
          "/tmp/com.openjoystickdriver.daemon.out",
          inFileViewerRootedAtPath: ""
        )
      }
      .buttonStyle(.borderless)

      SwiftUI.Button("Quit") { NSApplication.shared.terminate(nil) }
        .buttonStyle(.borderless)

      Spacer()
    }
    .font(.caption)
  }

  private var updateRow: some View {
    OJDCard(title: "Updates") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(updateStatusLine)
            .font(.caption)
            .foregroundColor(updateStatusColor)
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
          SwiftUI.Button(updateButtonTitle) {
            Task { await model.checkForUpdates() }
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .disabled(model.updateCheckState == .checking)
        }

        if case .available(let info) = model.updateCheckState {
          HStack(spacing: 8) {
            Text("OpenJoystickDriver \(info.tagName) is available.")
              .font(.caption)
              .foregroundColor(.orange)
            Spacer()
            SwiftUI.Button("Open") { model.openLatestRelease() }
              .buttonStyle(.borderless)
              .controlSize(.small)
          }
        }
      }
    }
  }

  private var updateButtonTitle: String {
    model.updateCheckState == .checking ? "Checking…" : "Check"
  }

  private var updateStatusLine: String {
    switch model.updateCheckState {
    case .idle: return "Current version \(model.appVersion)."
    case .checking: return "Checking GitHub releases…"
    case .upToDate(let version): return "OpenJoystickDriver \(version) is current."
    case .available: return "Update available."
    case .failed(let message): return "Update check failed: \(message)"
    }
  }

  private var updateStatusColor: Color {
    switch model.updateCheckState {
    case .upToDate: return .green
    case .available, .failed: return .orange
    default: return .secondary
    }
  }
}
