import AppKit
import OpenJoystickDriverKit
import SwiftUI

extension MenuBarPopoverView {
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
      SwiftUI.Button(L10n.string("app.refresh")) {
        Task { await model.syncFromApplicationServiceNow() }
      }
      .buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("button.showLog")) {
        for stream in ApplicationServiceLogStream.allCases {
          NSWorkspace.shared.selectFile(
            ApplicationServiceLogService.url(for: stream).path,
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
