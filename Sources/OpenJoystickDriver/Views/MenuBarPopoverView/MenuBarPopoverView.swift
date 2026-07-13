import AppKit
import OpenJoystickDriverKit
import SwiftUI

enum MenuBarConfirmationAction: String, Identifiable {
  case applicationServiceUninstall
  case systemExtensionUninstall
  case resetSettings

  var id: String { rawValue }
}

struct MenuBarPopoverView: View {
  @EnvironmentObject var model: AppModel
  @State var runningSelfTest = false
  @State var pendingConfirmation: MenuBarConfirmationAction?
  @State var showAdvanced = false
  @State var inputTester = InputTestWindowController()

  var gameControllerSupportLabel: String {
    guard let devices = model.virtualDeviceDiagnostics?.hidGamepads else {
      return L10n.string("service.status.unknown")
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
          applicationServiceCard
          selfTestRow
          supportReportRow
          updateRow
          footerRow
        }
      }
      .padding(14)
    }
    .frame(width: 440)
    .alert(item: $pendingConfirmation) { action in
      confirmationAlert(for: action)
    }
  }

  func confirmationAlert(for action: MenuBarConfirmationAction) -> Alert {
    switch action {
    case .applicationServiceUninstall:
      return Alert(
        title: Text("Remove Login Item?"),
        message: Text("OpenJoystickDriver will no longer start automatically at login."),
        primaryButton: .destructive(Text(L10n.string("app.uninstall"))) {
          Task {
            await model.uninstallApplicationService()
            await model.syncFromApplicationServiceNow()
          }
        },
        secondaryButton: .cancel()
      )
    case .systemExtensionUninstall:
      return Alert(
        title: Text(L10n.string("alert.systemExtensionUninstallTitle")),
        message: Text(L10n.string("alert.systemExtensionUninstallMessage")),
        primaryButton: .destructive(Text(L10n.string("app.uninstall"))) {
          model.extensionManager.uninstallExtension()
        },
        secondaryButton: .cancel()
      )
    case .resetSettings:
      return Alert(
        title: Text(L10n.string("alert.resetSettingsTitle")),
        message: Text(L10n.string("alert.resetSettingsMessage")),
        primaryButton: .destructive(Text(L10n.string("settings.reset"))) {
          Task { await model.resetSettings() }
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
    let permissionsReady = model.permissionsReady
    let ready = model.serviceConnected && permissionsReady
    let title = ready ? L10n.string("readiness.ready") : L10n.string("readiness.needsAttention")
    let summary: String = {
      switch model.applicationServiceUIState {
      case .restarting:
        return L10n.string("readiness.serviceRestarting")
      case .crashLooping:
        return L10n.string("readiness.serviceCrashLooping")
      case .missing:
        return L10n.string("readiness.installService")
      case .stopped:
        return L10n.string("readiness.startService")
      case .runningDisconnected:
        return L10n.string("readiness.serviceDisconnected")
      case .runningConnected, .unknown:
        break
      }
      if !model.serviceInstalled { return L10n.string("readiness.installService") }
      if !model.serviceConnected { return L10n.string("readiness.startService") }
      if model.inputMonitoringState != .granted {
        return L10n.string("readiness.allowAppInputMonitoring")
      }
      if model.accessibilityState != .granted {
        return "Allow Accessibility for the compatibility virtual gamepad."
      }
      if model.devices.isEmpty { return L10n.string("readiness.connectController") }
      return model.devices.count == 1
        ? L10n.string("readiness.controllersConnected.one", model.devices.count)
        : L10n.string("readiness.controllersConnected.other", model.devices.count)
    }()

    return OJDCard {
      HStack(alignment: .top, spacing: 12) {
        StatusOrb(isReady: ready, isBusy: model.serviceRestarting)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
          Text(summary)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Text(model.applicationServiceStatusLabel)
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

      if let err = model.serviceError {
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
    if model.serviceRestarting {
      EmptyView()
    } else if !model.permissionsReady {
      SwiftUI.Button(L10n.string("button.requestAccess")) {
        Task { await model.requestRequiredAccess() }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if !model.serviceInstalled {
      SwiftUI.Button(L10n.string("button.installService")) {
        Task {
          await model.installApplicationService()
          await model.syncFromApplicationServiceNow()
        }
      }
      .controlSize(.small)
      .padding(.top, 2)
    } else if !model.serviceConnected {
      if model.applicationServiceUIState == .stopped
        || model.applicationServiceUIState == .unknown
      {
        SwiftUI.Button(L10n.string("button.startService")) {
          Task {
            await model.startApplicationService()
            await model.syncFromApplicationServiceNow()
          }
        }
        .controlSize(.small)
        .padding(.top, 2)
      } else {
        SwiftUI.Button(L10n.string("button.restartService")) {
          Task {
            await model.restartApplicationService()
            await model.syncFromApplicationServiceNow()
          }
        }
        .controlSize(.small)
        .padding(.top, 2)
      }
    }
  }


  var gameProfileCard: some View {
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
            .disabled(!model.serviceConnected)
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
          .disabled(!model.serviceConnected || !compatSelected)
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
