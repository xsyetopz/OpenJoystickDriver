import AppKit
import OpenJoystickDriverKit
import SwiftUI

extension MenuBarPopoverView {
  var applicationServiceCard: some View {
    OJDCard(title: L10n.string("service.cardTitle")) {
      VStack(alignment: .leading, spacing: 10) {
        if let h = model.serviceHealth, h.installed {
          let state = h.state ?? "unknown"
          let pid = h.pid.map { "\($0)" } ?? "?"
          HStack(spacing: 8) {
            Text("Main app \(state), pid \(pid)")
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(2)
            Spacer()
            SwiftUI.Button(L10n.string("app.refresh")) {
              Task { await model.refreshApplicationServiceHealth() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
          }
        } else {
          Text(L10n.string("service.autoStarts"))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Divider()

        HStack(spacing: 8) {
          Text(L10n.string("service.systemExtension"))
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
          SwiftUI.Button(L10n.string("app.uninstall")) {
            pendingConfirmation = .systemExtensionUninstall
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .foregroundColor(.secondary)
          .disabled(
            !model.extensionManager.installState.isInstalled ||
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
          if !model.serviceInstalled {
            SwiftUI.Button(L10n.string("button.installService")) {
              Task {
                await model.installApplicationService()
                await model.syncFromApplicationServiceNow()
              }
            }
            .controlSize(.small)
          } else {
            SwiftUI.Button(L10n.string("app.start")) {
              Task {
                await model.startApplicationService()
                await model.syncFromApplicationServiceNow()
              }
            }
            .controlSize(.small)
            .disabled(
              model.applicationServiceUIState == .runningConnected
                || model.applicationServiceUIState == .runningDisconnected
                || model.applicationServiceUIState == .restarting
                || model.applicationServiceUIState == .crashLooping
            )
            SwiftUI.Button(L10n.string("app.restart")) {
              Task {
                await model.restartApplicationService()
                await model.syncFromApplicationServiceNow()
              }
            }
            .controlSize(.small)
            .disabled(model.serviceRestarting)
            SwiftUI.Button(L10n.string("app.uninstall")) {
              pendingConfirmation = .applicationServiceUninstall
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundColor(.secondary)
            .disabled(model.serviceRestarting)
          }
        }
      }
    }
  }

  var permissionsCard: some View {
    OJDCard(title: L10n.string("permissions.title")) {
      VStack(alignment: .leading, spacing: 8) {
        PermissionRow(
          title: "Input Monitoring",
          subtitle: permissionSubtitle(
            for: model.inputMonitoring,
            owner: L10n.string("permissions.ownerApp")
          ),
          state: model.inputMonitoring,
          actionTitle: permissionActionTitle(for: model.inputMonitoring)
        ) {
          Task { await model.requestRequiredAccess() }
        }
        PermissionRow(
          title: "Accessibility",
          subtitle: permissionSubtitle(
            for: model.accessibility,
            owner: L10n.string("permissions.ownerApp"),
            settingsName: "Accessibility"
          ),
          state: model.accessibility,
          actionTitle: permissionActionTitle(for: model.accessibility)
        ) {
          Task { await model.requestRequiredAccess() }
        }
        if let assist = model.inputMonitoringAssist {
          PermissionAssistView(message: assist)
        }
        Text(
          "Input Monitoring reads physical controller reports. Accessibility authorizes "
            + "the compatibility virtual gamepad. Both permissions belong to this app."
        )
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          SwiftUI.Button("Input Monitoring Settings") {
            model.openInputMonitoringSettings()
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          SwiftUI.Button("Accessibility Settings") {
            model.openAccessibilitySettings()
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
        }
      }
    }
  }

  func permissionActionTitle(for state: String) -> String {
    state == "granted" ? L10n.string("access.allowed") : L10n.string("button.requestAccess")
  }

  func permissionSubtitle(
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
}
