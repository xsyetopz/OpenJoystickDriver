#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  struct SystemExtensionSetupCard: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let supportReport: SupportReportModel
    @ObservedObject
    var navigation: SettingsNavigationModel
    @State
    private var confirmsUninstall = false

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            StatusBadge(status: statusLabel, semanticState: semanticState)
            Spacer()
            Button(OJDLocalized.string("common.refresh")) {
              Task { @MainActor in await viewModel.refreshSystemExtensionSetup() }
            }
          }
          Text(detail).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
          HStack {
            if viewModel.systemExtensionSetupState == .awaitingApproval {
              Button(
                OJDLocalized.string("setup.openSystemSettings"),
                action: openSettings
              )
            }
            if viewModel.systemExtensionSetupState == .needsActivation
              || viewModel.systemExtensionSetupState == .failed
              || viewModel.systemExtensionSetupState == .invalid
            {
              Button(OJDLocalized.string("setup.repairDriver")) {
                Task { @MainActor in await viewModel.repairSystemExtension() }
              }
            }
            Button(OJDLocalized.string("setup.controllerTest")) {
              navigation.requestPane(.controllers)
            }
            Button(OJDLocalized.string("setup.copySupportReport")) {
              Task { @MainActor in _ = await supportReport.copySupportReport() }
            }
            if viewModel.systemExtensionSetupState == .active {
              OJDDestructiveButton(
                action: { confirmsUninstall = true },
                label: {
                  Text(OJDLocalized.string("cli.login.uninstall_action"))
                }
              )
            }
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("setup.driverTitle")).font(.headline)
      }.ojdAccessibilityLabel(
        OJDLocalized.string("setup.driverAccessibility")
      ).ojdAccessibilityValue(detail).alert(isPresented: $confirmsUninstall) {
        Alert(
          title: Text(OJDLocalized.string("cli.login.uninstall_action")),
          message: Text(
            OJDLocalized.string(
              "setup.repairDetail"
            )
          ),
          primaryButton: .destructive(
            Text(OJDLocalized.string("cli.login.uninstall_action"))
          ) { Task { @MainActor in await viewModel.uninstallSystemExtension() } },
          secondaryButton: .cancel()
        )
      }
    }

    private var statusLabel: String {
      switch viewModel.systemExtensionSetupState {
      case .checking: return OJDLocalized.string("setup.checking")
      case .missingEmbedded, .invalid, .failed:
        return OJDLocalized.string("common.needsAttention")
      case .needsActivation, .replacementNeeded:
        return OJDLocalized.string("setup.activating")
      case .awaitingApproval:
        return OJDLocalized.string("setup.approvalNeeded")
      case .active: return OJDLocalized.string("status.ready")
      }
    }

    private var semanticState: SemanticState {
      switch viewModel.systemExtensionSetupState {
      case .active: return .healthy
      case .checking, .needsActivation, .replacementNeeded: return .loading
      case .awaitingApproval: return .attention
      case .missingEmbedded, .invalid, .failed: return .failure
      }
    }

    private var detail: String {
      switch viewModel.systemExtensionSetupState {
      case .checking:
        return OJDLocalized.string(
          "setup.checkingDetail"
        )
      case .missingEmbedded:
        return OJDLocalized.string(
          "setup.missingDetail"
        )
      case .invalid:
        return OJDLocalized.string(
          "setup.invalidDetail"
        )
      case .needsActivation, .replacementNeeded, .failed:
        return OJDLocalized.string(
          "setup.repairDetail"
        )
      case .awaitingApproval:
        return OJDLocalized.string(
          "setup.approvalDetail"
        )
      case .active:
        return OJDLocalized.string(
          "setup.activeDetail"
        )
      }
    }

    private func openSettings() {
      let urls = [
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
        URL(string: "x-apple.systempreferences:com.apple.preferences.extensions"),
      ].compactMap { $0 }
      for url in urls where NSWorkspace.shared.open(url) { return }
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
  }

#endif
