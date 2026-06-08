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
      return L10n.string("daemon.status.unknown")
    }
    let ojdDevices = devices.filter { $0.isOJDUserSpace || $0.isOJDDriverKit }
    if ojdDevices.isEmpty { return L10n.string("gameController.noOJDDevice") }
    if ojdDevices.contains(where: { $0.isGameControllerSupported == true }) {
      return L10n.string("gameController.yes")
    }
    if ojdDevices.contains(where: { $0.isGameControllerSupported == nil }) {
      return L10n.string("gameController.unknownOnMacOS")
    }
    return L10n.string("gameController.no")
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
          daemonCard
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
        title: Text(L10n.string("alert.uninstallTitle")),
        message: Text(L10n.string("alert.uninstallMessage")),
        primaryButton: .destructive(Text(L10n.string("app.uninstall"))) {
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
        Text(L10n.string("app.name"))
          .font(.system(size: 17, weight: .semibold))
      }
      Spacer()
      SwiftUI.Button(L10n.string("app.quit")) { NSApplication.shared.terminate(nil) }
        .buttonStyle(.borderless)
        .foregroundColor(.secondary)
    }
  }

  private var readinessCard: some View {
    let permissionsReady =
      model.appInputMonitoring == "granted" && model.inputMonitoring == "granted"
    let ready = model.daemonConnected && permissionsReady
    let title = ready ? L10n.string("readiness.ready") : L10n.string("readiness.needsAttention")
    let summary: String = {
      switch model.daemonUIState {
      case .restarting:
        return L10n.string("readiness.daemonRestarting")
      case .crashLooping:
        return L10n.string("readiness.daemonCrashLooping")
      case .missing:
        return L10n.string("readiness.installDaemon")
      case .stopped:
        return L10n.string("readiness.startDaemon")
      case .runningDisconnected:
        return L10n.string("readiness.daemonDisconnected")
      case .runningConnected, .unknown:
        break
      }
      if !model.daemonInstalled { return L10n.string("readiness.installDaemon") }
      if !model.daemonConnected { return L10n.string("readiness.startDaemon") }
      if model.appInputMonitoring != "granted" {
        return L10n.string("readiness.allowAppInputMonitoring")
      }
      if model.inputMonitoring != "granted" {
        return L10n.string("readiness.allowDaemonInputMonitoring")
      }
      if model.devices.isEmpty { return L10n.string("readiness.connectController") }
      return model.devices.count == 1
        ? L10n.string("readiness.controllersConnected.one", model.devices.count)
        : L10n.string("readiness.controllersConnected.other", model.devices.count)
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
        MetricChip(title: L10n.string("metric.controllers"), value: "\(model.devices.count)")
        MetricChip(title: L10n.string("metric.profile"), value: compatibilityIdentityLabel)
        MetricChip(
          title: L10n.string("metric.access"),
          value: permissionsReady
            ? L10n.string("access.allowed")
            : L10n.string("access.needsAccess")
        )
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
      SwiftUI.Button(L10n.string("button.requestAccess")) {
        Task { await model.requestAppInputMonitoringAccess() }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if model.inputMonitoring != "granted" {
      SwiftUI.Button(L10n.string("button.requestAccess")) {
        Task { await model.requestDaemonInputMonitoringAccess() }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if !model.daemonInstalled {
      SwiftUI.Button(L10n.string("button.installDaemon")) {
        Task {
          await model.installDaemon()
          await model.syncFromDaemonNow()
        }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if !model.daemonConnected {
      if model.daemonUIState == .stopped || model.daemonUIState == .unknown {
        SwiftUI.Button(L10n.string("button.startDaemon")) {
          Task {
            await model.startDaemon()
            await model.syncFromDaemonNow()
          }
        }
        .controlSize(.small)
        .padding(.top, 2)
      } else {
        SwiftUI.Button(L10n.string("button.restartDaemon")) {
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

  private var daemonCard: some View {
    OJDCard(title: L10n.string("daemon.cardTitle")) {
      VStack(alignment: .leading, spacing: 10) {
        if let h = model.daemonHealth, h.installed {
          let state = h.state ?? "unknown"
          let pid = h.pid.map { "\($0)" } ?? "?"
          let runs = h.runs.map { "\($0)" } ?? "?"
          let reason = h.isInefficientKillLoop ? (h.immediateReason ?? h.blame) : nil
          let reasonText = reason.map { L10n.string("daemon.launchdReason", $0) } ?? ""
          HStack(spacing: 8) {
            Text(L10n.string("daemon.launchdStatus", state, pid, runs, reasonText))
              .font(.caption)
              .foregroundColor(h.isInefficientKillLoop ? .orange : .secondary)
              .lineLimit(2)
            Spacer()
            SwiftUI.Button(L10n.string("app.refresh")) {
              Task { await model.refreshDaemonHealth() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
          }
        } else {
          Text(L10n.string("daemon.autoStarts"))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Divider()

        HStack(spacing: 8) {
          Text(L10n.string("daemon.systemExtension"))
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Text(model.extensionManager.installState.label)
            .font(.caption.weight(.semibold))
            .foregroundColor(model.extensionManager.installState.isInstalled ? .green : .secondary)
          SwiftUI.Button(L10n.string("app.install")) { model.extensionManager.installExtension() }
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
            SwiftUI.Button(L10n.string("button.installDaemon")) {
              Task {
                await model.installDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
          } else {
            SwiftUI.Button(L10n.string("app.start")) {
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
            SwiftUI.Button(L10n.string("app.restart")) {
              Task {
                await model.restartDaemon()
                await model.syncFromDaemonNow()
              }
            }
            .controlSize(.small)
            .disabled(model.daemonRestarting)
            SwiftUI.Button(L10n.string("app.uninstall")) { showUninstallConfirm = true }
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
    OJDCard(title: L10n.string("permissions.title")) {
      VStack(alignment: .leading, spacing: 8) {
        PermissionRow(
          title: L10n.string("app.name"),
          subtitle: permissionSubtitle(
            for: model.appInputMonitoring,
            owner: L10n.string("permissions.ownerApp")
          ),
          state: model.appInputMonitoring,
          actionTitle: permissionActionTitle(for: model.appInputMonitoring)
        ) {
          Task { await model.requestAppInputMonitoringAccess() }
        }
        Divider()
        PermissionRow(
          title: L10n.string("permissions.daemonName"),
          subtitle: permissionSubtitle(
            for: model.inputMonitoring,
            owner: L10n.string("permissions.ownerDaemon"),
            settingsName: L10n.string("permissions.daemonName")
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
    state == "granted" ? L10n.string("access.allowed") : L10n.string("button.requestAccess")
  }

  private func permissionSubtitle(
    for state: String,
    owner: String,
    settingsName: String? = nil
  ) -> String {
    switch state {
    case "granted":
      return L10n.string("permissions.accessAllowed")
    case "denied":
      let name = settingsName ?? owner
      return L10n.string("permissions.openSettings", name)
    default:
      return L10n.string("permissions.requestAccessDefault")
    }
  }

  private var gameProfileCard: some View {
    OJDCard(title: L10n.string("profile.cardTitle")) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string("profile.description"))
              .font(.caption)
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          if model.virtualDeviceMode != VirtualDeviceMode.compatUserSpace.rawValue {
            SwiftUI.Button(L10n.string("button.useCompatibility")) {
              Task { await model.setVirtualDeviceMode(VirtualDeviceMode.compatUserSpace.rawValue) }
            }
            .controlSize(.small)
            .disabled(!model.daemonConnected)
          }
        }

        let compatSelected = model.virtualDeviceMode == VirtualDeviceMode.compatUserSpace.rawValue
        HStack(spacing: 10) {
          Text(L10n.string("profile.identity"))
            .font(.caption)
            .foregroundColor(.secondary)
          Picker(
            "Compatibility identity",
            selection: Binding(
              get: { model.compatibilityIdentity },
              set: { v in Task { await model.setCompatibilityIdentity(v) } }
            )
          ) {
            Text(L10n.string("profile.sdl")).tag(CompatibilityIdentity.sdl2_3.rawValue)
            Text(L10n.string("profile.appleGameController"))
              .tag(CompatibilityIdentity.appleGameController.rawValue)
            Text(L10n.string("profile.genericHID")).tag(CompatibilityIdentity.genericHID.rawValue)
            Text(L10n.string("profile.xbox360HID")).tag(CompatibilityIdentity.x360HID.rawValue)
            Text(L10n.string("profile.xboxOneHID")).tag(CompatibilityIdentity.xoneHID.rawValue)
          }
          .frame(maxWidth: .infinity)
          .disabled(!model.daemonConnected || !compatSelected)
        }

        if !compatSelected {
          Text(L10n.string("profile.switchToCompatibility"))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  private var outputDetailsCard: some View {
    OJDCard(title: L10n.string("output.detailsCardTitle")) {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          L10n.string("output.mode"),
          selection: Binding(
            get: { model.virtualDeviceMode },
            set: { newValue in Task { await model.setVirtualDeviceMode(newValue) } }
          )
        ) {
          Text(L10n.string("output.auto")).tag(VirtualDeviceMode.auto.rawValue)
          Text(L10n.string("output.driverKit")).tag(VirtualDeviceMode.driverKit.rawValue)
          Text(L10n.string("output.compatibility")).tag(VirtualDeviceMode.compatUserSpace.rawValue)
          if model.developerMode {
            Text(L10n.string("output.both")).tag(VirtualDeviceMode.both.rawValue)
          }
        }
        .pickerStyle(.segmented)
        .disabled(!model.daemonConnected)

        VStack(alignment: .leading, spacing: 3) {
          statusLine(L10n.string("output.active"), activeOutputLabel)
          statusLine(
            L10n.string("output.backend"),
            model.userSpaceVirtualDeviceStatus,
            warning: model.userSpaceVirtualDeviceStatus.hasPrefix("error:")
          )
          statusLine(
            L10n.string("output.gameController"),
            gameControllerSupportLabel,
            success: gameControllerSupportLabel == L10n.string("gameController.yes")
          )
          if let s = model.virtualDeviceDiagnostics?.driverKitOutputStats {
            statusLine(
              L10n.string("output.driverKitReports"),
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
    case CompositeOutputDispatcher.Mode.primaryOnly.rawValue: return L10n.string("output.driverKit")
    case CompositeOutputDispatcher.Mode.secondaryOnly.rawValue:
      return L10n.string("output.compatibility")
    case CompositeOutputDispatcher.Mode.both.rawValue: return L10n.string("output.both")
    default: return L10n.string("output.unknown")
    }
  }

  private var compatibilityIdentityLabel: String {
    switch model.compatibilityIdentity {
    case CompatibilityIdentity.sdl2_3.rawValue:
      return L10n.string("identity.sdlShort")
    case CompatibilityIdentity.appleGameController.rawValue:
      return L10n.string("output.gameController")
    case CompatibilityIdentity.genericHID.rawValue: return L10n.string("profile.genericHID")
    case CompatibilityIdentity.x360HID.rawValue:
      return L10n.string("identity.xbox360Short")
    case CompatibilityIdentity.xoneHID.rawValue:
      return L10n.string("identity.xboxOneShort")
    default: return model.compatibilityIdentity
    }
  }

  private var selfTestRow: some View {
    OJDCard(title: L10n.string("selfTest.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L10n.string("selfTest.description"))
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        SwiftUI.Button(
          runningSelfTest ? L10n.string("selfTest.running") : L10n.string("selfTest.run5s")
        ) {
          runningSelfTest = true
          Task {
              await model.syncFromDaemonNow()
            if model.daemonHealth?.isInefficientKillLoop == true {
              model.daemonError =
                L10n.string("selfTest.daemonKillLoop")
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
            L10n.string("output.driverKit"),
            "value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)"
          )
          if let delta = t.driverKitInputReportDelta {
            statusLine(L10n.string("output.ioregInput"), "Δ \(delta)")
          }
          if let delta = t.driverKitSetReportSuccessDelta {
            statusLine(L10n.string("output.daemonSetReport"), "ok Δ \(delta)")
          }
          statusLine(
            L10n.string("output.userSpace"),
            "value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)"
          )
        }
      } else {
        Text(L10n.string("selfTest.pressButtons"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      }
    }
  }

  private var inputTestRow: some View {
    OJDCard(title: L10n.string("input.title")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(L10n.string("inputTest.description"))
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          SwiftUI.Button(L10n.string("button.openInputTest")) {
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
        Text(
          showAdvanced
            ? L10n.string("advanced.hideDetails")
            : L10n.string("advanced.showDetails")
        )
        Spacer()
        Text(showAdvanced ? L10n.string("advanced.collapse") : L10n.string("advanced.expand"))
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
      SwiftUI.Button(L10n.string("app.refresh")) {
        Task {
          await model.syncFromDaemonNow()
        }
      }
      .buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("button.showLog")) {
        NSWorkspace.shared.selectFile(
          "/tmp/com.openjoystickdriver.daemon.out",
          inFileViewerRootedAtPath: ""
        )
      }
      .buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("app.quit")) { NSApplication.shared.terminate(nil) }
        .buttonStyle(.borderless)

      Spacer()
    }
    .font(.caption)
  }

  private var updateRow: some View {
    OJDCard(title: L10n.string("updates.cardTitle")) {
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

        Toggle(L10n.string("updates.includePrereleases"), isOn: $model.includePrereleaseUpdates)
          .font(.caption)
          .toggleStyle(.checkbox)
          .disabled(model.updateCheckState == .checking)

        if case .available(let info) = model.updateCheckState {
          HStack(spacing: 8) {
            Text(L10n.string("updates.available", info.tagName))
              .font(.caption)
              .foregroundColor(.orange)
            Spacer()
            SwiftUI.Button(L10n.string("app.open")) { model.openLatestRelease() }
              .buttonStyle(.borderless)
              .controlSize(.small)
          }
        }
      }
    }
  }

  private var updateButtonTitle: String {
    model.updateCheckState == .checking
      ? L10n.string("updates.checking")
      : L10n.string("updates.check")
  }

  private var updateStatusLine: String {
    switch model.updateCheckState {
    case .idle: return L10n.string("updates.currentVersion", model.appVersion)
    case .checking: return L10n.string("updates.checkingGithub")
    case .upToDate(let version): return L10n.string("updates.current", version)
    case .available: return L10n.string("updates.updateAvailable")
    case .failed(let message): return L10n.string("updates.checkFailed", message)
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
