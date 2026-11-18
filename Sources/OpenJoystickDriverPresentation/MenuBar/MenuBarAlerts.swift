#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  /// The alerts the menu bar app shows, built apart from `runModal` so a test reads what the
  /// person sees.
  enum MenuBarAlerts {
    /// Whether `response` is the first button, the one that confirms.
    static func isConfirmed(_ response: NSApplication.ModalResponse) -> Bool {
      response == .alertFirstButtonReturn
    }

    /// The tour choice that the button behind `response` stands for, or nil for any other response.
    static func tourChoice(
      response: NSApplication.ModalResponse,
      choices: [MainWindowTour.Choice]
    ) -> MainWindowTour.Choice? {
      let pressed = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
      return choices.indices.contains(pressed) ? choices[pressed] : nil
    }

    /// An alert with a title, a message and an OK button.
    @MainActor
    static func notice(
      title: String,
      message: String,
      style: NSAlert.Style = .informational
    ) -> NSAlert {
      let alert = NSAlert()
      alert.alertStyle = style
      alert.messageText = title
      alert.informativeText = message
      alert.addButton(withTitle: OJDLocalized.string("action.ok")).toolTip =
        OJDLocalized.string("ui.help.dismissMessage")
      return alert
    }

    /// An alert that names the failed action and gives `message`.
    @MainActor
    static func failure(message: String) -> NSAlert {
      notice(
        title: OJDLocalized.string("ui.extra.actionFailedTitle"),
        message: message,
        style: .warning
      )
    }

    /// The confirmation to disconnect a wireless controller: Disconnect, marked destructive, then
    /// Cancel.
    @MainActor
    static func disconnectWireless(_ confirmation: WirelessDisconnectConfirmation) -> NSAlert {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = confirmation.title
      alert.informativeText = confirmation.message
      let disconnect = alert.addButton(withTitle: confirmation.confirmTitle)
      disconnect.hasDestructiveAction = true
      disconnect.toolTip = OJDLocalized.string("ui.help.disconnectWireless")
      alert.addButton(withTitle: OJDLocalized.string("action.cancel")).toolTip =
        OJDLocalized.string("ui.help.cancelAlert")
      return alert
    }

    /// The confirmation to activate a profile: the notice's message, or the warning about a profile
    /// with no output, then Set Active and Cancel.
    @MainActor
    static func activation(_ confirmation: ProfileEditorConfirmation) -> NSAlert {
      let alert = NSAlert()
      alert.alertStyle = .warning
      if case .activateNotice(let message) = confirmation {
        alert.messageText = OJDLocalized.string("ui.profiles.activationTitle")
        alert.informativeText = message
      } else {
        alert.messageText = OJDLocalized.string("ui.profiles.emptyActivationTitle")
        alert.informativeText = OJDLocalized.string("ui.profiles.emptyActivationMessage")
      }
      alert.addButton(withTitle: OJDLocalized.string("action.setActive")).toolTip =
        OJDLocalized.string("ui.help.confirmActivation")
      alert.addButton(withTitle: OJDLocalized.string("action.cancel")).toolTip =
        OJDLocalized.string("ui.help.cancelAlert")
      return alert
    }

    /// The alert of one tour step, with a button for each of `choices` in order.
    @MainActor
    static func tourStep(
      _ step: MainWindowTour.Step,
      choices: [MainWindowTour.Choice]
    ) -> NSAlert {
      let alert = NSAlert()
      alert.alertStyle = .informational
      alert.icon = NSImage(systemSymbolName: step.area.symbolName, accessibilityDescription: nil)
      alert.messageText = OJDLocalized.string(step.titleKey)
      alert.informativeText = OJDLocalized.string(step.summaryKey)
      for choice in choices {
        switch choice {
        case .next:
          alert.addButton(withTitle: OJDLocalized.string("ui.tour.next")).toolTip =
            OJDLocalized.string("ui.help.tourNext")
        case .back:
          alert.addButton(withTitle: OJDLocalized.string("ui.tour.back")).toolTip =
            OJDLocalized.string("ui.help.tourBack")
        case .done:
          alert.addButton(withTitle: OJDLocalized.string("action.done")).toolTip =
            OJDLocalized.string("ui.help.tourDone")
        }
      }
      return alert
    }
  }

#endif
