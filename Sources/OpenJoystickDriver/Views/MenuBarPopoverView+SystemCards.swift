import AppKit
import OpenJoystickDriverKit
import SwiftUI

extension MenuBarPopoverView {
  var daemonCard: some View {
    OJDCard(title: L10n.string("daemon.cardTitle")) {
      VStack(alignment: .leading, spacing: 10) {
        if let h = model.daemonHealth, h.installed {
          let state = h.state ?? "unknown"
          let pid = h.pid.map { "\($0)" } ?? "?"
          let runs = h.runs.map { "\($0)" } ?? "?"
          let reason = h.isInefficientKillLoop ? (h.immediateReason ?? h.blame) : nil
          let reasonText = reason.map { L10n.string("daemon.launchdReason", $0) } ?? ""
          HStack(spacing: 8) {
            Text(L10n.string("daemon.launchdStatus", state, pid, runs, reasonText)).font(.caption)
              .foregroundColor(h.isInefficientKillLoop ? .orange : .secondary).lineLimit(2)
            Spacer()
            SwiftUI.Button(L10n.string("app.refresh")) {
              Task { await model.refreshDaemonHealth() }
            }.buttonStyle(.borderless).controlSize(.small)
          }
        } else {
          Text(L10n.string("daemon.autoStarts")).font(.caption).foregroundColor(.secondary)
        }

        Divider()

        HStack(spacing: 8) {
          Text(L10n.string("daemon.systemExtension")).font(.caption).foregroundColor(.secondary)
          Spacer()
          Text(model.extensionManager.installState.label).font(.caption.weight(.semibold))
            .foregroundColor(model.extensionManager.installState.isInstalled ? .green : .secondary)
          SwiftUI.Button(L10n.string("app.install")) { model.extensionManager.installExtension() }
            .controlSize(.small).disabled(
              model.extensionManager.installState.isInstalled
                || model.extensionManager.installState.isPending
            )
        }
        if case .failed(let msg) = model.extensionManager.installState {
          Text(msg).font(.caption).foregroundColor(.red).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        if let warning = model.extensionManager.installWarning,
          model.extensionManager.installState.isInstalled
        {
          Text(warning).font(.caption).foregroundColor(.orange).fixedSize(
            horizontal: false,
            vertical: true
          )
        }

        HStack(spacing: 8) {
          if !model.daemonInstalled {
            SwiftUI.Button(L10n.string("button.installDaemon")) {
              Task {
                await model.installDaemon()
                await model.syncFromDaemonNow()
              }
            }.controlSize(.small)
          } else {
            SwiftUI.Button(L10n.string("app.start")) {
              Task {
                await model.startDaemon()
                await model.syncFromDaemonNow()
              }
            }.controlSize(.small).disabled(
              model.daemonUIState == .runningConnected
                || model.daemonUIState == .runningDisconnected || model.daemonUIState == .restarting
                || model.daemonUIState == .crashLooping
            )
            SwiftUI.Button(L10n.string("app.restart")) {
              Task {
                await model.restartDaemon()
                await model.syncFromDaemonNow()
              }
            }.controlSize(.small).disabled(model.daemonRestarting)
            SwiftUI.Button(L10n.string("app.uninstall")) { showUninstallConfirm = true }
              .buttonStyle(.borderless).controlSize(.small).foregroundColor(.secondary).disabled(
                model.daemonRestarting
              )
          }
        }
      }
    }
  }

  var permissionsCard: some View {
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
        ) { Task { await model.requestAppInputMonitoringAccess() } }
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
        ) { Task { await model.requestDaemonInputMonitoringAccess() } }
        Divider()
        Text("Accessibility (optional)").font(.caption.weight(.semibold))
          .foregroundColor(.secondary)
        PermissionRow(
          title: "OpenJoystickDriver Accessibility",
          subtitle: accessibilitySubtitle(for: model.appAccessibility, owner: "OpenJoystickDriver"),
          state: model.appAccessibility,
          actionTitle: permissionActionTitle(for: model.appAccessibility)
        ) { Task { await model.requestAppAccessibilityAccess() } }
        PermissionRow(
          title: "OpenJoystickDriver Daemon Accessibility",
          subtitle: accessibilitySubtitle(
            for: model.daemonAccessibility,
            owner: "OpenJoystickDriver Daemon"
          ),
          state: model.daemonAccessibility,
          actionTitle: permissionActionTitle(for: model.daemonAccessibility),
          disabled: model.daemonRestarting
        ) { Task { await model.requestDaemonAccessibilityAccess() } }
        if let assist = model.inputMonitoringAssist { PermissionAssistView(message: assist) }
      }
    }
  }

  func permissionActionTitle(for state: String) -> String {
    state == "granted" ? L10n.string("access.allowed") : L10n.string("button.requestAccess")
  }

  func accessibilitySubtitle(for state: String, owner: String) -> String {
    switch state {
    case "granted": return "Accessibility is allowed."
    case "denied": return "Open System Settings, then turn on Accessibility for \(owner) if asked."
    default: return "Optional fallback for macOS permission prompts if the daemon asks for it."
    }
  }

  func permissionSubtitle(for state: String, owner: String, settingsName: String? = nil) -> String {
    switch state {
    case "granted": return L10n.string("permissions.accessAllowed")
    case "denied":
      let name = settingsName ?? owner
      return L10n.string("permissions.openSettings", name)
    default: return L10n.string("permissions.requestAccessDefault")
    }
  }
}
