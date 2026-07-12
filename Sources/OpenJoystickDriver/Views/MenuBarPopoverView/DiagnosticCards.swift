import AppKit
import OpenJoystickDriverKit
import SwiftUI

extension MenuBarPopoverView {
  var appleGameControllerCatalogRow: some View {
    OJDCard(title: L10n.string("appleCatalog.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 10) {
          Text(L10n.string("appleCatalog.description")).font(.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
          SwiftUI.Button(
            model.appleGameControllerAuditRunning
              ? L10n.string("appleCatalog.scanning") : L10n.string("appleCatalog.scan")
          ) { Task { await model.runAppleGameControllerAudit() } }.controlSize(.small).disabled(
            model.appleGameControllerAuditRunning
          )
        }

        if let audit = model.appleGameControllerAudit {
          statusLine(
            L10n.string("appleCatalog.version"),
            audit.bundleVersions.isEmpty
              ? L10n.string("appleCatalog.unavailable")
              : audit.bundleVersions.joined(separator: ", ")
          )
          statusLine(L10n.string("appleCatalog.appleEntries"), "\(audit.appleExactDeviceCount)")
          statusLine(
            L10n.string("appleCatalog.ojdListed"),
            "\(audit.catalogListedOJDRecordCount)/\(audit.ojdRecordCount)",
            warning: audit.source == .unavailable
          )
          statusLine(
            L10n.string("appleCatalog.compatibilityListed"),
            "\(audit.appleBackedCompatibilityProfileCount)/"
              + "\(audit.hardwareSpoofCompatibilityProfileCount)",
            warning: audit.appleBackedCompatibilityProfileCount
              < audit.hardwareSpoofCompatibilityProfileCount
          )
          Text(L10n.string("appleCatalog.caveat")).font(.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  var browserGamepadDiagnosticRow: some View {
    OJDCard(title: L10n.string("browserDiagnostic.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.string("browserDiagnostic.description")).font(.caption).foregroundColor(
          .secondary
        ).fixedSize(horizontal: false, vertical: true)

        Picker(L10n.string("browserDiagnostic.browser"), selection: $browserGamepadTarget) {
          ForEach(BrowserGamepadTarget.allCases, id: \.rawValue) { target in
            Text(browserGamepadTargetLabel(target)).tag(target)
          }
        }.disabled(model.browserGamepadDiagnosticRunning)

        HStack(spacing: 10) {
          Text(L10n.string("browserDiagnostic.port")).font(.caption).foregroundColor(.secondary)
          TextField(
            "",
            text: Binding(
              get: { String(browserGamepadPort) },
              set: { value in if let port = Int(value) { browserGamepadPort = port } }
            )
          ).frame(width: 68).disabled(model.browserGamepadDiagnosticRunning)

          Stepper(
            L10n.string("browserDiagnostic.duration", browserGamepadSeconds),
            value: $browserGamepadSeconds,
            in: 1...3_600,
            step: 1
          ).font(.caption).disabled(model.browserGamepadDiagnosticRunning)
        }

        HStack(spacing: 8) {
          SwiftUI.Button(
            model.browserGamepadDiagnosticRunning
              ? L10n.string("browserDiagnostic.stop") : L10n.string("browserDiagnostic.run")
          ) {
            if model.browserGamepadDiagnosticRunning {
              model.stopBrowserGamepadDiagnostic()
            } else {
              Task {
                await model.startBrowserGamepadDiagnostic(
                  port: browserGamepadPort,
                  seconds: browserGamepadSeconds,
                  target: browserGamepadTarget
                )
              }
            }
          }.controlSize(.small)

          if model.browserGamepadDiagnosticRunning {
            Text(L10n.string("browserDiagnostic.running")).font(.caption.weight(.semibold))
              .foregroundColor(.green)
          }
        }

        if model.browserGamepadSnapshotCount > 0 {
          Text(L10n.string("browserDiagnostic.snapshotCount", model.browserGamepadSnapshotCount))
            .font(.caption).foregroundColor(.secondary)
        }

        if let url = model.browserGamepadDiagnosticURL {
          Text(L10n.string("browserDiagnostic.url", url.absoluteString)).font(.caption)
            .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if let error = model.browserGamepadDiagnosticError {
          Text(error).font(.caption).foregroundColor(.orange).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
      }
    }
  }

  private func browserGamepadTargetLabel(_ target: BrowserGamepadTarget) -> String {
    switch target {
    case .none: return L10n.string("browserDiagnostic.target.none")
    case .systemDefault: return L10n.string("browserDiagnostic.target.default")
    case .safari: return "Safari"
    case .chrome: return "Google Chrome"
    case .firefox: return "Firefox"
    case .all: return L10n.string("browserDiagnostic.target.all")
    }
  }

  var supportReportRow: some View {
    OJDCard(title: L10n.string("supportReport.cardTitle")) {
      HStack(alignment: .top, spacing: 10) {
        Text(L10n.string("supportReport.description")).font(.caption).foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        SwiftUI.Button(
          model.creatingSupportReport
            ? L10n.string("supportReport.saving") : L10n.string("supportReport.save")
        ) { Task { await model.saveSupportReport() } }.controlSize(.small).disabled(
          model.creatingSupportReport
        )
      }
    }
  }

  var advancedToggle: some View {
    SwiftUI.Button {
      showAdvanced.toggle()
    } label: {
      HStack {
        Text(
          showAdvanced ? L10n.string("advanced.hideDetails") : L10n.string("advanced.showDetails")
        )
        Spacer()
        Text(showAdvanced ? L10n.string("advanced.collapse") : L10n.string("advanced.expand"))
      }.font(.caption.weight(.semibold)).foregroundColor(.secondary).padding(.horizontal, 12)
        .padding(.vertical, 8).background(
          RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08))
        )
    }.buttonStyle(.plain)
  }

  var footerRow: some View {
    HStack(spacing: 10) {
      SwiftUI.Button(L10n.string("app.refresh")) { Task { await model.syncFromDaemonNow() } }
        .buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("button.showLog")) {
        for stream in DaemonLogStream.allCases {
          NSWorkspace.shared.selectFile(
            DaemonLogService.url(for: stream).path,
            inFileViewerRootedAtPath: ""
          )
        }
      }.buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("app.quit")) { NSApplication.shared.terminate(nil) }.buttonStyle(
        .borderless
      )

      Spacer()
    }.font(.caption)
  }

  var updateRow: some View {
    OJDCard(title: L10n.string("updates.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(updateStatusLine).font(.caption).foregroundColor(updateStatusColor).fixedSize(
            horizontal: false,
            vertical: true
          )
          Spacer()
          SwiftUI.Button(updateButtonTitle) { Task { await model.checkForUpdates() } }.buttonStyle(
            .borderless
          ).controlSize(.small).disabled(model.updateCheckState == .checking)
        }

        if !model.sparkleUpdates.isConfigured {
          Toggle(L10n.string("updates.includePrereleases"), isOn: $model.includePrereleaseUpdates)
            .font(.caption).toggleStyle(.checkbox).disabled(model.updateCheckState == .checking)
        }

        if case .available(let info) = model.updateCheckState {
          HStack(spacing: 8) {
            Text(L10n.string("updates.available", info.tagName)).font(.caption).foregroundColor(
              .orange
            )
            Spacer()
            SwiftUI.Button(L10n.string("app.open")) { model.openLatestRelease() }.buttonStyle(
              .borderless
            ).controlSize(.small)
          }
        }
      }
    }
  }

  var updateButtonTitle: String {
    model.updateCheckState == .checking
      ? L10n.string("updates.checking") : L10n.string("updates.check")
  }

  var updateStatusLine: String {
    if model.sparkleUpdates.isConfigured {
      return L10n.string("updates.currentVersion", model.appVersion)
    }

    switch model.updateCheckState {
    case .idle: return L10n.string("updates.currentVersion", model.appVersion)
    case .checking: return L10n.string("updates.checkingGithub")
    case .upToDate(let version): return L10n.string("updates.current", version)
    case .available: return L10n.string("updates.updateAvailable")
    case .failed(let message): return L10n.string("updates.checkFailed", message)
    }
  }

  var updateStatusColor: Color {
    switch model.updateCheckState {
    case .upToDate: return .green
    case .available, .failed: return .orange
    default: return .secondary
    }
  }
}
