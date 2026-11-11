#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  /// Makes the image of the menu-bar item.
  enum MenuBarStatusItemImage {
    /// Returns the symbol as a template image, or nil when the symbol is missing.
    static func make(symbolName: String, accessibilityDescription: String) -> NSImage? {
      let image = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: accessibilityDescription
      )
      image?.isTemplate = true
      return image
    }
  }

  /// Runs the app: the menu-bar item, the main window, the Settings window and the main menu.
  @MainActor
  package final class MenuBarCoordinator: NSObject, NSApplicationDelegate {
    /// Stops the runtime at quit.
    let stopRuntime: @MainActor () async -> Void
    /// The runtime state that every window reads.
    let viewModel: RuntimeViewModel
    /// The view model of the status menu.
    let menuBarViewModel: MenuBarViewModel
    /// The support report and log export model.
    let supportReport: SupportReportModel
    /// The service gateway for requests and for the input test.
    let gateway: any ApplicationServiceGateway & InputTestDeviceGateway
    /// The source of the service's change notifications.
    let gatewayChangeSource: any ControllerChangeSource

    /// The menu-bar item, or nil while it is hidden.
    var statusItem: NSStatusItem?
    /// Tells when the user takes the menu-bar item out of the menu bar.
    var statusItemVisibilityObservation: NSKeyValueObservation?
    /// The menu of the menu-bar item.
    var statusMenu: NSMenu?
    /// Tells when the status menu opens and closes.
    let statusMenuTracker = StatusMenuTracker()
    /// The main window; the status item and main menu open areas only through it.
    var mainWindow: (any MenuProfileMutating)?
    /// The Settings window.
    var settingsWindow: (any SettingsWindowPresenting)?
    /// App preferences, shared with the Settings window; `showInMenuBar` adds or removes the
    /// status item and `showInDock` the Dock icon.
    let preferences: SettingsPreferencesModel
    /// The command-line tool link, shown by the Settings window.
    let commandLineTool = CommandLineToolModel()
    /// Applies Show in menu bar when its setting changes.
    var showInMenuBarObservation: AnyCancellable?
    /// Applies Show in Dock when its setting changes.
    var showInDockObservation: AnyCancellable?
    /// Pauses and resumes every controller from the pause shortcut.
    var pauseHotKey: PauseHotKey?
    /// Registers the pause shortcut when its setting changes.
    var pauseShortcutObservation: AnyCancellable?
    /// The Input Test window, created when the first one opens.
    var inputTestWindowController: InputTestWindowController?
    /// Keeps the app in step with the service's changes while it runs.
    var controllerLiveUpdates: ControllerLiveUpdates?
    /// Turns changes of the service state into notifications.
    let notificationMonitor = RuntimeNotificationMonitor()
    /// Presents notifications and handles the user's answer.
    let notificationPresenter = RuntimeNotificationCenterDelegate()
    /// Makes every way of quitting wait for the same teardown.
    let termination = MenuBarTermination()
    /// Sets the Dock icon from Show in Dock and the open windows.
    let dockIcon = DockIconController.appKit()
    /// The running coordinator, which a shutdown signal quits.
    static weak var activeCoordinator: MenuBarCoordinator?

    /// Creates the coordinator with the runtime, its models and the service gateway.
    package init(
      stopRuntime: @escaping @MainActor () async -> Void,
      gateway: ApplicationServiceClientGateway,
      systemExtensionSetup: any SystemExtensionSetupClient,
      listenerState: ServiceListenerState
    ) {
      self.stopRuntime = stopRuntime
      self.gateway = gateway
      self.gatewayChangeSource = gateway
      self.preferences = SettingsPreferencesModel(testNotifications: gateway)
      self.viewModel = RuntimeViewModel(
        gateway: gateway,
        systemExtensionSetup: SystemExtensionSetupCoordinator(client: systemExtensionSetup),
        listenerState: listenerState
      )
      self.menuBarViewModel = MenuBarViewModel(runtime: self.viewModel)
      self.supportReport = SupportReportModel(gateway: gateway)
      super.init()
    }
  }

#else

  /// A placeholder on a platform without AppKit and SwiftUI.
  final class MenuBarCoordinator {}

#endif
