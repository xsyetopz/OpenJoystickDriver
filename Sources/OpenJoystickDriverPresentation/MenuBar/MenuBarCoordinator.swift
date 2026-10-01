#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  enum MenuBarStatusItemImage {
    static let statusItemSize = NSSize(width: 18, height: 18)

    static func make(applicationIcon: NSImage?, accessibilityDescription: String) -> NSImage? {
      if let icon = scaledApplicationIcon(applicationIcon) { return icon }
      return templateSymbol(accessibilityDescription: accessibilityDescription)
    }

    static func scaledApplicationIcon(_ icon: NSImage?) -> NSImage? {
      guard let icon, icon.isValid, !icon.representations.isEmpty else { return nil }
      guard icon.size.width > 0, icon.size.height > 0 else { return nil }
      guard let copy = icon.copy() as? NSImage else { return nil }
      copy.size = statusItemSize
      return copy
    }

    static func templateSymbol(accessibilityDescription: String) -> NSImage? {
      let image = NSImage(
        systemSymbolName: "gamecontroller",
        accessibilityDescription: accessibilityDescription
      )
      image?.isTemplate = true
      return image
    }
  }

  @MainActor
  package final class MenuBarCoordinator: NSObject, NSApplicationDelegate {
    let stopRuntime: @MainActor () async -> Void
    let viewModel: RuntimeViewModel
    let menuBarViewModel: MenuBarViewModel
    let supportReport: SupportReportModel
    let gateway: any ApplicationServiceGateway & InputTestDeviceGateway

    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    var settingsWindowController: SettingsWindowController?
    var inputTestWindowController: InputTestWindowController?
    var liveStatusTimer: Timer?
    var controllerInventoryObserver: NSObjectProtocol?
    let notificationMonitor = RuntimeNotificationMonitor()
    let notificationPresenter = RuntimeNotificationCenterDelegate()
    let termination = MenuBarTermination()
    let primaryWindowVisibility = PrimaryWindowVisibilityController()
    static weak var activeCoordinator: MenuBarCoordinator?

    package init(
      stopRuntime: @escaping @MainActor () async -> Void,
      gateway: ApplicationServiceClientGateway,
      systemExtensionSetup: any SystemExtensionSetupClient
    ) {
      self.stopRuntime = stopRuntime
      self.gateway = gateway
      self.viewModel = RuntimeViewModel(
        gateway: gateway,
        systemExtensionSetup: SystemExtensionSetupCoordinator(client: systemExtensionSetup)
      )
      self.menuBarViewModel = MenuBarViewModel(runtime: self.viewModel)
      self.supportReport = SupportReportModel(gateway: gateway)
      super.init()
    }
  }

#else

  final class MenuBarCoordinator {}

#endif
