import AppKit
import OpenJoystickDriverKit
import SwiftUI

struct MenuBarPopoverView: View {
  @EnvironmentObject var model: AppModel
  @State var runningSelfTest = false
  @State var showUninstallConfirm = false
  @State var showAdvanced = false
  @State var inputTester = InputTestWindowController()

  var gameControllerSupportLabel: String {
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

  var permissionsGranted: Bool {
    model.appInputMonitoring == "granted"
      && model.inputMonitoring == "granted"
      && model.compatibilityAccessibilityGranted
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
          showUninstallConfirm = false
          Task {
            await model.uninstallDaemon()
            await model.syncFromDaemonNow()
          }
        },
        secondaryButton: .cancel()
      )
    }
  }

  var headerRow: some View {
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

  var readinessCard: some View {
    let permissionsReady = permissionsGranted
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
      if !model.compatibilityAccessibilityGranted {
        return L10n.string("readiness.allowDaemonAccessibility")
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
  var readinessAction: some View {
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
    } else if !model.compatibilityAccessibilityGranted {
      SwiftUI.Button(L10n.string("button.requestAccess")) {
        Task { await model.requestCompatibilityAccessibilityAccess() }
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


  var gameProfileCard: some View {
    PermissionLockedContent(isLocked: !permissionsGranted) {
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
                Task {
                  await model.setVirtualDeviceMode(VirtualDeviceMode.compatUserSpace.rawValue)
                }
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
  }

}
