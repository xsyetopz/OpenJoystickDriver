#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  struct SystemExtensionSetupCard: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @ObservedObject var navigation: SettingsNavigationModel

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            StatusBadge(status: statusLabel, symbol: symbol)
            Spacer()
            Button(OJDLocalized.string("common.refresh", fallback: "Refresh")) {
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
                OJDLocalized.string("setup.openSystemSettings", fallback: "Open System Settings"),
                action: openSettings
              )
            }
            if viewModel.systemExtensionSetupState == .needsActivation
              || viewModel.systemExtensionSetupState == .failed
              || viewModel.systemExtensionSetupState == .invalid
            {
              Button(OJDLocalized.string("setup.repairDriver", fallback: "Repair Xbox USB Driver"))
              { Task { @MainActor in await viewModel.repairSystemExtension() } }
            }
            Button(OJDLocalized.string("setup.controllerTest", fallback: "Controller Test")) {
              navigation.requestPane(.controllers)
            }
            Button(OJDLocalized.string("setup.copySupportReport", fallback: "Copy Support Report"))
            { Task { @MainActor in _ = await viewModel.copySupportReport() } }
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("setup.driverTitle", fallback: "Xbox USB Driver")).font(.headline)
      }.ojdAccessibilityLabel(
        OJDLocalized.string("setup.driverAccessibility", fallback: "Xbox USB Driver setup")
      ).ojdAccessibilityValue(detail)
    }

    private var statusLabel: String {
      switch viewModel.systemExtensionSetupState {
      case .checking: return OJDLocalized.string("setup.checking", fallback: "Checking...")
      case .missingEmbedded, .invalid, .failed:
        return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
      case .needsActivation, .replacementNeeded:
        return OJDLocalized.string("setup.activating", fallback: "Activating...")
      case .awaitingApproval:
        return OJDLocalized.string("setup.approvalNeeded", fallback: "Approval needed")
      case .active: return OJDLocalized.string("status.ready", fallback: "Ready")
      }
    }

    private var symbol: String {
      viewModel.systemExtensionSetupState == .active ? "checkmark.circle" : "exclamationmark.circle"
    }

    private var detail: String {
      switch viewModel.systemExtensionSetupState {
      case .checking:
        return OJDLocalized.string(
          "setup.checkingDetail",
          fallback: "Checking the installed Xbox USB driver."
        )
      case .missingEmbedded:
        return OJDLocalized.string(
          "setup.missingDetail",
          fallback: "This app does not contain the Xbox USB driver. Reinstall the signed app."
        )
      case .invalid:
        return OJDLocalized.string(
          "setup.invalidDetail",
          fallback: "The embedded Xbox USB driver is invalid. Repair by reinstalling this app."
        )
      case .needsActivation, .replacementNeeded, .failed:
        return OJDLocalized.string(
          "setup.repairDetail",
          fallback: "OpenJoystickDriver will repair the Xbox USB driver without developer tools."
        )
      case .awaitingApproval:
        return OJDLocalized.string(
          "setup.approvalDetail",
          fallback:
            "Approve the driver in System Settings to use supported Microsoft USB controllers."
        )
      case .active:
        return OJDLocalized.string(
          "setup.activeDetail",
          fallback: "The restricted Xbox USB driver is installed and ready."
        )
      }
    }

    private func openSettings() {
      let urls = [
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
        URL(string: "x-apple.systempreferences:com.apple.preferences.extensions")
      ].compactMap { $0 }
      for url in urls where NSWorkspace.shared.open(url) { return }
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
  }

#endif
