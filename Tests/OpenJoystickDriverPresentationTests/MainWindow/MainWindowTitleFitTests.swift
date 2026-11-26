import AppKit
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
extension MainWindowController {
  /// A main window controller over stubs whose window stays behind the desktop picture, and the
  /// call that removes its defaults suite.
  ///
  /// A test may order the window in or attach a sheet to it; neither appears in front of the
  /// person at the Mac.
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
    controller.window?.keepUnseen()
    return (controller, { defaults.removePersistentDomain(forName: suiteName) })
  }
}

@Suite
@MainActor
struct MainWindowTitleFitTests {
  @Test(arguments: [false, true])
  func titleAndSubtitleEndInsideListColumn(sidebarCollapsed: Bool) async throws {
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let window = try #require(controller.window)
    controller.navigation.requestArea(.profiles)
    controller.splitViewController.splitViewItems[0].isCollapsed = sidebarCollapsed
    window.title = "Profile und Zuweisungen der Controller"
    window.layoutIfNeeded()
    let splitView = controller.splitViewController.splitView
    splitView.setPosition(splitView.arrangedSubviews[1].frame.minX, ofDividerAt: 1)
    let titleEdges = {
      window.layoutIfNeeded()
      return MainWindowTitleFit.textEdges(of: window)
    }
    await waitUntil("the title text ends inside the list column", deadline: 10) {
      let edges = titleEdges()
      return !edges.isEmpty && edges.allSatisfy { $0 <= splitView.arrangedSubviews[1].frame.maxX }
    }

    let listEdge = splitView.arrangedSubviews[1].frame.maxX
    let edges = titleEdges()
    #expect(!edges.isEmpty)
    for edge in edges { #expect(edge <= listEdge) }
  }
}
