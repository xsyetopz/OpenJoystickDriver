#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Debug

  struct DebugView: View {
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          PageHeader(title: OJDLocalized.string("debug.title", fallback: "Debug"))
          VStack(alignment: .leading, spacing: 14) {
            statusSummary.frame(maxWidth: .infinity, alignment: .leading)
            debugReportCard.frame(maxWidth: .infinity, alignment: .leading)
          }
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
      }.onAppear {
        if case .idle = viewModel.supportDiagnosticsState {
          Task { @MainActor in await viewModel.loadSupportDiagnostics() }
        }
      }
    }

    private var statusSummary: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text(OJDLocalized.string("debug.currentStatus", fallback: "Current status")).font(
            .headline
          )
          statusSummaryContent
        }.padding(4)
      }.ojdAccessibilityLabel(
        OJDLocalized.string("debug.currentStatus", fallback: "Current status")
      )
    }

    @ViewBuilder private var statusSummaryContent: some View {
      switch viewModel.statusState {
      case .loading:
        LoadingStateView(
          message: OJDLocalized.string(
            "status.checkingRuntime",
            fallback: "Checking runtime status..."
          )
        )
      case .available(let status):
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 12) {
            StatusMatrixCell(
              label: OJDLocalized.string("debug.runtime", fallback: "Runtime"),
              value: status.readinessLabel
            )
            StatusMatrixCell(
              label: OJDLocalized.string("common.controllers", fallback: "Controllers"),
              value: status.deviceCountLabel
            )
          }
          StatusMatrixCell(
            label: OJDLocalized.string(
              "common.controllerIdentity",
              fallback: "Controller identity"
            ),
            value: status.compatibilityLabel
          )
        }
      case .unavailable(let message):
        StatusMatrixCell(
          label: OJDLocalized.string("debug.runtime", fallback: "Runtime"),
          value: OJDLocalized.string("common.unavailable", fallback: "Unavailable")
        )
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      case .error(let message):
        StatusMatrixCell(
          label: OJDLocalized.string("debug.runtime", fallback: "Runtime"),
          value: OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
        )
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }

    private var debugReportCard: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text(OJDLocalized.string("debug.diagnostics", fallback: "Diagnostics")).font(.headline)
          diagnosticsContent
          HStack(spacing: 8) {
            Button(OJDLocalized.string("debug.collect", fallback: "Collect")) {
              Task { @MainActor in await viewModel.loadSupportDiagnostics() }
            }.ojdAccessibilityLabel(
              OJDLocalized.string("debug.collectAccessibility", fallback: "Collect diagnostics")
            ).disabled(isCollectingDiagnostics)
            Button(
              OJDLocalized.string("debug.saveReport", fallback: "Save report..."),
              action: presentSavePanel
            ).disabled(isSavingReport)
            Button(
              OJDLocalized.string("debug.saveLogs", fallback: "Save logs..."),
              action: presentSaveLogsPanel
            ).disabled(isSavingLogs)
          }
          reportStatus
          logsStatus
        }.padding(4)
      }
    }

    @ViewBuilder private var diagnosticsContent: some View {
      switch viewModel.supportDiagnosticsState {
      case .idle:
        Text(OJDLocalized.string("debug.noneYet", fallback: "No diagnostics collected yet."))
          .foregroundColor(Color(NSColor.secondaryLabelColor))
      case .loading:
        LoadingStateView(
          message: OJDLocalized.string("debug.collecting", fallback: "Collecting diagnostics...")
        )
      case .available(let details):
        VStack(alignment: .leading, spacing: 6) {
          KeyValueRow(
            label: OJDLocalized.string("common.service", fallback: "Service"),
            value: details.virtualControllerOutputLabel
          )
          KeyValueRow(
            label: OJDLocalized.string("common.devices", fallback: "Devices"),
            value: diagnosticDeviceCountLabel(details.virtualControllerCount)
          )
        }
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "debug.diagnosticsUnavailable",
            fallback: "Diagnostics unavailable"
          ),
          message: message
        ) { Task { @MainActor in await viewModel.loadSupportDiagnostics() } }
      case .error(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "debug.diagnosticsNeedsAttention",
            fallback: "Diagnostics need attention"
          ),
          message: message
        ) { Task { @MainActor in await viewModel.loadSupportDiagnostics() } }
      }
    }

    private func diagnosticDeviceCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("debug.devices", count: count, fallback: "%d detected")
    }

    @ViewBuilder private var reportStatus: some View {
      switch viewModel.supportReportState {
      case .idle: EmptyView()
      case .saving:
        LoadingStateView(
          message: OJDLocalized.string("debug.savingReport", fallback: "Saving debug report...")
        ).ojdAccessibilityLabel(
          OJDLocalized.string("debug.savingReportAccessibility", fallback: "Saving debug report")
        )
      case .saved:
        Text(OJDLocalized.string("debug.reportSaved", fallback: "Debug report saved."))
          .foregroundColor(Color(NSColor.systemGreen))
      case .error(let message):
        Text(message).foregroundColor(Color(NSColor.systemRed)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }

    @ViewBuilder private var logsStatus: some View {
      switch viewModel.supportLogsState {
      case .idle: EmptyView()
      case .saving:
        LoadingStateView(
          message: OJDLocalized.string("debug.savingLogs", fallback: "Saving debug logs...")
        ).ojdAccessibilityLabel(
          OJDLocalized.string("debug.savingLogsAccessibility", fallback: "Saving debug logs")
        )
      case .saved:
        Text(OJDLocalized.string("debug.logsSaved", fallback: "Logs saved.")).foregroundColor(
          Color(NSColor.systemGreen)
        )
      case .error(let message):
        Text(message).foregroundColor(Color(NSColor.systemRed)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }

    private var isCollectingDiagnostics: Bool {
      if case .loading = viewModel.supportDiagnosticsState { return true }
      return false
    }

    private var isSavingReport: Bool {
      if case .saving = viewModel.supportReportState { return true }
      return false
    }

    private var isSavingLogs: Bool {
      if case .saving = viewModel.supportLogsState { return true }
      return false
    }

    private func presentSavePanel() {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("debug.saveReportPanel", fallback: "Save Debug Report")
      panel.nameFieldStringValue = viewModel.defaultSupportReportFilename
      panel.canCreateDirectories = true
      let viewModel = viewModel
      panel.begin { response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in await viewModel.saveSupportReport(to: outputURL) }
      }
    }

    private func presentSaveLogsPanel() {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("debug.saveLogsPanel", fallback: "Save Debug Logs")
      panel.nameFieldStringValue = viewModel.defaultSupportLogsFilename
      panel.canCreateDirectories = true
      let viewModel = viewModel
      panel.begin { response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in await viewModel.saveSupportLogs(to: outputURL) }
      }
    }
  }

  private struct StatusMatrixCell: View {
    let label: String
    let value: String

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        Text(value).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
        .ojdAccessibilityLabel(label).ojdAccessibilityValue(value)
    }
  }

  // MARK: - Shared presentation primitives

  struct PageHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
      self.title = title
      self.subtitle = subtitle
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.largeTitle.weight(.semibold))
        if let subtitle {
          Text(subtitle).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
      }
    }
  }

  struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(label).foregroundColor(Color(NSColor.secondaryLabelColor))
        Spacer(minLength: 8)
        Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
      }
    }
  }

  struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        OJDSystemSymbol(
          name: symbol,
          fallback: OJDLocalized.string("common.status", fallback: "Status")
        ).font(.title).foregroundColor(Color(NSColor.controlAccentColor))
        Text(title).font(.headline)
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }.padding(.vertical, 12)
    }
  }

  struct LoadingStateView: View {
    let message: String

    var body: some View {
      HStack(spacing: 8) {
        if #available(macOS 11.0, *) {
          ProgressView()
        } else {
          Text(OJDLocalized.string("common.loadingEllipsis", fallback: "..."))
        }
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }
  }

  struct ServiceFailureStateView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
      GroupBox {
        HStack(alignment: .top, spacing: 10) {
          OJDSystemSymbol(name: "exclamationmark.triangle", fallback: "!").foregroundColor(
            Color(NSColor.systemRed)
          )
          VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
            Button(OJDLocalized.string("common.tryAgain", fallback: "Try again"), action: retry)
          }
          Spacer(minLength: 0)
        }.padding(4)
      }.ojdAccessibilityLabel(title).ojdAccessibilityValue(message)
    }
  }

  struct OJDLoadingIndicator: View {
    var body: some View {
      if #available(macOS 11.0, *) {
        ProgressView()
      } else {
        Text(OJDLocalized.string("common.loadingEllipsis", fallback: "..."))
      }
    }
  }

#endif
