#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// The Xbox USB driver extension section of Settings > Advanced: its state, and Uninstall while
  /// it is active.
  ///
  /// Problems with the driver show in the main window's problem banner.
  struct DriverExtensionSection: View {
    /// The driver extension state and its uninstall action.
    @ObservedObject
    var runtime: RuntimeViewModel
    /// Whether the Uninstall confirmation alert is open.
    @State
    private var confirmsUninstall = false

    /// The driver extension status and its uninstall button, with the confirmation.
    var body: some View {
      Section(OJDLocalized.string("ui.setup.driverTitle")) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(OJDLocalized.string(detailKey)).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          if runtime.systemExtensionSetupState == .active {
            Button(OJDLocalized.string("cli.login.group.uninstallAction")) {
              confirmsUninstall = true
            }
          }
        }
      }.alert(isPresented: $confirmsUninstall) {
        Alert(
          title: Text(OJDLocalized.string("cli.login.group.uninstallAction")),
          message: Text(OJDLocalized.string("ui.setup.uninstallDetail")),
          primaryButton: .destructive(Text(OJDLocalized.string("cli.login.group.uninstallAction")))
          {
            Task { @MainActor in await runtime.uninstallSystemExtension() }
          },
          secondaryButton: .cancel()
        )
      }
    }

    /// The localization key of the sentence that describes the driver extension state.
    private var detailKey: String {
      switch runtime.systemExtensionSetupState {
      case .checking: return "ui.setup.checkingDetail"
      case .active: return "ui.setup.activeDetail"
      case .missingEmbedded: return "ui.setup.missingDetail"
      case .invalid: return "ui.setup.invalidDetail"
      case .awaitingApproval: return "platform.macos.ui.setup.approvalDetail"
      case .needsActivation, .replacementNeeded, .failed: return "ui.setup.repairDetail"
      }
    }
  }

#endif
