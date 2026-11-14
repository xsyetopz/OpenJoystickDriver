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
    /// Whether the extension was still active after the latest Uninstall.
    @State
    private var uninstallLeftActive = false

    /// The driver extension status and its uninstall button, with the confirmation.
    var body: some View {
      Section(OJDLocalized.string("ui.setup.driverTitle")) {
        HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.medium) {
          Text(OJDLocalized.string(detailKey)).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          if runtime.systemExtensionSetupState == .active {
            Button(OJDLocalized.string("cli.login.group.uninstallAction")) {
              confirmsUninstall = true
            }.help(OJDLocalized.string("ui.help.uninstallDriver"))
          }
        }
        if uninstallLeftActive, runtime.systemExtensionSetupState == .active {
          Text(OJDLocalized.string("ui.setup.uninstallRefused")).foregroundColor(
            Color(NSColor.systemRed)
          ).fixedSize(horizontal: false, vertical: true)
        }
      }.alert(isPresented: $confirmsUninstall) {
        Alert(
          title: Text(OJDLocalized.string("cli.login.group.uninstallAction")),
          message: Text(OJDLocalized.string("ui.setup.uninstallDetail")),
          primaryButton: .destructive(Text(OJDLocalized.string("cli.login.group.uninstallAction")))
          {
            Task { @MainActor in
              await runtime.uninstallSystemExtension()
              uninstallLeftActive = runtime.systemExtensionSetupState == .active
            }
          },
          secondaryButton: .cancel()
        )
      }
    }

    /// The localization key of the text that describes the driver extension state.
    private var detailKey: String {
      switch runtime.systemExtensionSetupState {
      case .checking: return "status.checking"
      case .active: return "ui.library.installed"
      case .missingEmbedded: return "ui.setup.missingDetail"
      case .invalid: return "ui.setup.invalidDetail"
      case .unavailable: return "ui.setup.unavailableDetail"
      case .running: return "ui.setup.runningDetail"
      case .needsApproval: return "platform.macos.ui.setup.approvalDetail"
      case .cancelled: return "ui.setup.cancelledDetail"
      case .timedOut: return "ui.setup.timedOutDetail"
      case .failed: return "ui.setup.failedDetail"
      case .needsActivation, .replacementNeeded: return "ui.setup.repairDetail"
      }
    }
  }

#endif
