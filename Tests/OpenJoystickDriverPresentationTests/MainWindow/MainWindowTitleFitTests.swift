import AppKit
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
extension MainWindowController {
  /// A main window controller over stubs whose window never goes on screen, and the call that
  /// removes its defaults suite.
  static func offScreen() throws -> (MainWindowController, cleanup: () -> Void) {
    let suiteName = "MainWindowController.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let controller = MainWindowController(
      runtime: RuntimeViewModel(gateway: GatewayStub()),
      supportReport: SupportReportModel(gateway: GatewayStub()),
      preferences: SettingsPreferencesModel(
        testNotifications: TestNotificationRequestStub(),
        settings: SettingsStore(directory: RootedDataDirectory.temporary()),
        launchAtLogin: LaunchAtLoginStub(isEnabled: false),
        notificationAuthorization: NotificationAuthorizationStub(state: .denied)
      ),
      restartApplication: {},
      openInputTest: { _ in },
      visibilityChanged: { _ in },
      persistence: UserDefaultsMainWindowAreaPersistence(defaults: defaults)
    )
    return (controller, { defaults.removePersistentDomain(forName: suiteName) })
  }
}

@Suite
@MainActor
struct MainWindowTitleFitTests {
  @Test(arguments: [false, true])
  func titleAndSubtitleEndInsideListColumn(sidebarCollapsed: Bool) throws {
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let window = try #require(controller.window)
    controller.navigation.requestArea(.profiles)
    controller.splitViewController.splitViewItems[0].isCollapsed = sidebarCollapsed
    window.title = "Profile und Zuweisungen der Controller"
    window.layoutIfNeeded()
    let splitView = controller.splitViewController.splitView
    splitView.setPosition(splitView.arrangedSubviews[1].frame.minX, ofDividerAt: 1)
    RunLoop.main.run(until: .now.addingTimeInterval(0.2))
    window.layoutIfNeeded()

    let listEdge = splitView.arrangedSubviews[1].frame.maxX
    let edges = MainWindowTitleFit.textEdges(of: window)
    #expect(!edges.isEmpty)
    for edge in edges { #expect(edge <= listEdge) }
  }
}
