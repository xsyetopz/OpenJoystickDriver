import AppKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

/// The menu bar alerts show the text, buttons and tooltips the person is promised, and each button
/// response maps to one action.
@Suite
@MainActor
struct MenuBarAlertsTests {
  private static func tips(_ alert: NSAlert) -> [String] { alert.buttons.map { $0.toolTip ?? "" } }
  private static func titles(_ alert: NSAlert) -> [String] { alert.buttons.map(\.title) }

  @Test
  func disconnectWirelessAlertConfirmsWithADestructiveFirstButton() {
    let confirmation = WirelessDisconnectConfirmation(controllerName: "Pad A")
    let alert = MenuBarAlerts.disconnectWireless(confirmation)

    #expect(alert.alertStyle == .warning)
    #expect(
      alert.messageText == OJDLocalized.string("ui.controllers.disconnectWirelessConfirmTitle")
    )
    #expect(
      alert.informativeText
        == OJDLocalized.formatted("ui.controllers.disconnectWirelessConfirmMessage", "Pad A")
    )
    #expect(
      Self.titles(alert) == [
        OJDLocalized.string("ui.controllers.disconnectWirelessConfirm"),
        OJDLocalized.string("action.cancel"),
      ]
    )
    #expect(
      Self.tips(alert) == [
        OJDLocalized.string("ui.help.disconnectWireless"),
        OJDLocalized.string("ui.help.cancelAlert"),
      ]
    )
    #expect(alert.buttons[0].hasDestructiveAction)
    #expect(!alert.buttons[1].hasDestructiveAction)
  }

  @Test
  func firstButtonConfirmsAndEveryOtherResponseDeclines() {
    #expect(MenuBarAlerts.isConfirmed(.alertFirstButtonReturn))
    #expect(!MenuBarAlerts.isConfirmed(.alertSecondButtonReturn))
    #expect(!MenuBarAlerts.isConfirmed(.cancel))
  }

  @Test
  func activationNoticeAlertShowsTheNoticeMessage() {
    let alert = MenuBarAlerts.activation(.activateNotice("Needs a permission."))

    #expect(alert.alertStyle == .warning)
    #expect(alert.messageText == OJDLocalized.string("ui.profiles.activationTitle"))
    #expect(alert.informativeText == "Needs a permission.")
    #expect(
      Self.titles(alert) == [
        OJDLocalized.string("action.setActive"), OJDLocalized.string("action.cancel"),
      ]
    )
    #expect(
      Self.tips(alert) == [
        OJDLocalized.string("ui.help.confirmActivation"),
        OJDLocalized.string("ui.help.cancelAlert"),
      ]
    )
  }

  @Test
  func emptyActivationAlertWarnsAboutNoOutput() {
    let alert = MenuBarAlerts.activation(.activateEmpty)

    #expect(alert.alertStyle == .warning)
    #expect(alert.messageText == OJDLocalized.string("ui.profiles.emptyActivationTitle"))
    #expect(alert.informativeText == OJDLocalized.string("ui.profiles.emptyActivationMessage"))
    #expect(
      Self.titles(alert) == [
        OJDLocalized.string("action.setActive"), OJDLocalized.string("action.cancel"),
      ]
    )
  }

  @Test
  func failureAlertNamesTheFailedActionWithOneOKButton() {
    let alert = MenuBarAlerts.failure(message: "Busy.")

    #expect(alert.alertStyle == .warning)
    #expect(alert.messageText == OJDLocalized.string("ui.extra.actionFailedTitle"))
    #expect(alert.informativeText == "Busy.")
    #expect(Self.titles(alert) == [OJDLocalized.string("action.ok")])
    #expect(Self.tips(alert) == [OJDLocalized.string("ui.help.dismissMessage")])
  }

  @Test
  func noticeAlertDefaultsToInformationalAndTakesAStyle() {
    let plain = MenuBarAlerts.notice(title: "Title", message: "Message")
    let warning = MenuBarAlerts.notice(title: "Title", message: "Message", style: .warning)

    #expect(plain.alertStyle == .informational)
    #expect(warning.alertStyle == .warning)
    #expect(plain.messageText == "Title")
    #expect(plain.informativeText == "Message")
    #expect(Self.titles(plain) == [OJDLocalized.string("action.ok")])
    #expect(Self.tips(plain) == [OJDLocalized.string("ui.help.dismissMessage")])
  }

  @Test
  func tourAlertHasOneButtonPerChoiceInOrder() {
    var tour = MainWindowTour()
    let first = MenuBarAlerts.tourStep(tour.current, choices: tour.choices)

    #expect(first.alertStyle == .informational)
    #expect(first.messageText == OJDLocalized.string(tour.current.titleKey))
    #expect(first.informativeText == OJDLocalized.string(tour.current.summaryKey))
    #expect(
      Self.titles(first) == [
        OJDLocalized.string("ui.tour.next"), OJDLocalized.string("action.done"),
      ]
    )
    #expect(
      Self.tips(first) == [
        OJDLocalized.string("ui.help.tourNext"), OJDLocalized.string("ui.help.tourDone"),
      ]
    )

    tour.next()
    let middle = MenuBarAlerts.tourStep(tour.current, choices: tour.choices)
    #expect(
      Self.titles(middle) == [
        OJDLocalized.string("ui.tour.next"), OJDLocalized.string("ui.tour.back"),
        OJDLocalized.string("action.done"),
      ]
    )
    #expect(
      Self.tips(middle) == [
        OJDLocalized.string("ui.help.tourNext"), OJDLocalized.string("ui.help.tourBack"),
        OJDLocalized.string("ui.help.tourDone"),
      ]
    )

    while !tour.isLast { tour.next() }
    let last = MenuBarAlerts.tourStep(tour.current, choices: tour.choices)
    #expect(
      Self.titles(last) == [
        OJDLocalized.string("ui.tour.back"), OJDLocalized.string("action.done"),
      ]
    )
  }

  @Test
  func tourButtonsMapToChoicesAndOtherResponsesEndTheTour() {
    let choices: [MainWindowTour.Choice] = [.next, .back, .done]

    #expect(MenuBarAlerts.tourChoice(response: .alertFirstButtonReturn, choices: choices) == .next)
    #expect(MenuBarAlerts.tourChoice(response: .alertSecondButtonReturn, choices: choices) == .back)
    #expect(MenuBarAlerts.tourChoice(response: .alertThirdButtonReturn, choices: choices) == .done)
    #expect(MenuBarAlerts.tourChoice(response: .cancel, choices: choices) == nil)
    #expect(
      MenuBarAlerts.tourChoice(response: .alertThirdButtonReturn, choices: [.back, .done]) == nil
    )
  }

  @Test
  func unreadableSettingsAlertShowsItsTextStyleAndTooltips() {
    let alert = SettingsUnreadableAlert.make(reason: "Reason", offersMigration: true)

    #expect(alert.alertStyle == .warning)
    #expect(alert.messageText == OJDLocalized.string("ui.settings.advanced.unreadableTitle"))
    #expect(alert.informativeText == "Reason")
    #expect(
      Self.titles(alert) == [
        OJDLocalized.string("ui.migrate.action"),
        OJDLocalized.string("platform.macos.ui.settings.advanced.unreadableShowInFinder"),
        OJDLocalized.string("ui.settings.advanced.unreadableResetSettings"),
        MainMenuRenderer.title("ui.menu.app.quit", appName: OJDLocalized.string("term.app.name")),
      ]
    )
    #expect(
      Self.tips(alert) == [
        OJDLocalized.string("ui.help.migrate"),
        OJDLocalized.string("platform.macos.ui.help.showSettingsFile"),
        OJDLocalized.string("ui.help.resetSettings"),
        OJDLocalized.string("ui.help.menu.quit"),
      ]
    )
    let withoutMigration = SettingsUnreadableAlert.make(reason: "Reason")
    #expect(Self.tips(withoutMigration) == Array(Self.tips(alert).dropFirst()))
  }
}
