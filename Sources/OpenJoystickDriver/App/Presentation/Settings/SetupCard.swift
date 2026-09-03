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
            Button("Refresh") {
              Task { @MainActor in await viewModel.refreshSystemExtensionSetup() }
            }
          }
          Text(detail).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
          HStack {
            if viewModel.systemExtensionSetupState == .awaitingApproval {
              Button("Open System Settings", action: openSettings)
            }
            if viewModel.systemExtensionSetupState == .needsActivation
              || viewModel.systemExtensionSetupState == .failed
              || viewModel.systemExtensionSetupState == .invalid
            {
              Button("Repair Xbox USB Driver") {
                Task { @MainActor in await viewModel.repairSystemExtension() }
              }
            }
            Button("Controller Test") { navigation.requestPane(.controllers) }
            Button("Copy Support Report") {
              Task { @MainActor in _ = await viewModel.copySupportReport() }
            }
          }
        }.padding(4)
      } label: {
        Text("Xbox USB Driver").font(.headline)
      }.ojdAccessibilityLabel("Xbox USB Driver setup").ojdAccessibilityValue(detail)
    }

    private var statusLabel: String {
      switch viewModel.systemExtensionSetupState {
      case .checking: return "Checking…"
      case .missingEmbedded, .invalid, .failed: return "Needs attention"
      case .needsActivation, .replacementNeeded: return "Activating…"
      case .awaitingApproval: return "Approval needed"
      case .active: return "Ready"
      }
    }

    private var symbol: String {
      viewModel.systemExtensionSetupState == .active ? "checkmark.circle" : "exclamationmark.circle"
    }

    private var detail: String {
      switch viewModel.systemExtensionSetupState {
      case .checking: return "Checking the installed Xbox USB driver."
      case .missingEmbedded:
        return "This app does not contain the Xbox USB driver. Reinstall the signed app."
      case .invalid:
        return "The embedded Xbox USB driver is invalid. Repair by reinstalling this app."
      case .needsActivation, .replacementNeeded, .failed:
        return "OpenJoystickDriver will repair the Xbox USB driver without developer tools."
      case .awaitingApproval:
        return "Approve the driver in System Settings to use supported Microsoft USB controllers."
      case .active: return "The restricted Xbox USB driver is installed and ready."
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
