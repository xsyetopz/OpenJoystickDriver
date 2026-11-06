#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sizes of the Input Test window.
  enum InputTestWindowSizingPolicy {
    /// The size the window opens with.
    static let defaultContentSize = NSSize(width: 900, height: 620)
    /// The smallest size of the window's content.
    static let minimumContentSize = NSSize(width: 700, height: 500)

    /// Returns the size that keeps the content at least as big as the minimum.
    ///
    /// - Parameter current: The size of the content.
    /// - Returns: The size that keeps the content at least as big as the minimum.
    static func fittingContentSize(_ current: NSSize) -> NSSize {
      NSSize(
        width: max(current.width, minimumContentSize.width),
        height: max(current.height, minimumContentSize.height)
      )
    }
  }

  /// The title of the Input Test window.
  enum InputTestWindowTitle {
    /// Returns the title that names the physical controller, as the Controllers list does.
    ///
    /// - Parameter device: The controller.
    /// - Returns: The title that names the physical controller, as the Controllers list does.
    static func make(for device: ApplicationServiceDeviceDescription) -> String {
      OJDLocalized.formatted("ui.inputTest.windowTitle", device.name)
    }
  }

  /// The Input Test window, with a Refresh button in its toolbar.
  @MainActor
  final class InputTestWindowController: NSWindowController, NSWindowDelegate {
    /// The identifier of the window's toolbar.
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.InputTestToolbar"
    )
    /// The identifier of the Refresh toolbar item.
    private static let refreshIdentifier = NSToolbarItem.Identifier(
      "OpenJoystickDriver.InputTest.Refresh"
    )

    /// The state of the window.
    let model: InputTestViewModel
    /// The model of the app's view of the service, which Refresh refreshes.
    private let runtimeViewModel: RuntimeViewModel
    /// Called with true when the window shows and with false when it closes.
    private let visibilityChanged: @MainActor (Bool) -> Void

    /// Creates the window and its content; it autosaves its frame.
    ///
    /// - Parameters:
    ///   - gateway: The gateway to the service.
    ///   - runtimeViewModel: The model of the app's view of the service.
    ///   - visibilityChanged: Called when the window shows or closes.
    init(
      gateway: any InputTestDeviceGateway,
      runtimeViewModel: RuntimeViewModel,
      visibilityChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
      model = InputTestViewModel(gateway: gateway)
      self.runtimeViewModel = runtimeViewModel
      self.visibilityChanged = visibilityChanged
      let rootView = InputTestView(model: model, runtimeViewModel: runtimeViewModel)
      let host = NSHostingView(rootView: rootView)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: InputTestWindowSizingPolicy.defaultContentSize),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.contentMinSize = InputTestWindowSizingPolicy.minimumContentSize
      window.hidesOnDeactivate = false
      let autosaveName = "InputTestWindowGeometryV2"
      let restoredFrame = window.setFrameUsingName(autosaveName)
      window.setFrameAutosaveName(autosaveName)
      window.isReleasedWhenClosed = false
      window.contentView = host
      let restoredContentSize = window.contentView?.bounds.size ?? .zero
      window.setContentSize(InputTestWindowSizingPolicy.fittingContentSize(restoredContentSize))
      if !restoredFrame { window.center() }
      WindowFramePolicy.clamp(window)
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
    }

    /// Not supported; the window is created in code.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Selects the controller, starts the input session and shows the window.
    ///
    /// - Parameter device: The controller to test.
    func show(device: ApplicationServiceDeviceDescription) {
      model.selectDevice(device)
      window?.title = InputTestWindowTitle.make(for: device)
      model.open()
      visibilityChanged(true)
      if let window { WindowFramePolicy.clamp(window) }
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Ends the input session.
    func stop() { model.close() }

    /// Ends the session and hides the window instead of closing it.
    ///
    /// - Parameter sender: The window.
    /// - Returns: False, because the window stays alive.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
      model.close()
      sender.orderOut(nil)
      visibilityChanged(false)
      return false
    }

    /// Adds the toolbar with the Refresh item.
    ///
    /// - Parameter window: The window.
    private func configureToolbar(for window: NSWindow) {
      let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconAndLabel
      window.toolbar = toolbar
      toolbar.isVisible = true
    }

    /// Refreshes the controller inventory.
    ///
    /// - Parameter sender: The toolbar item.
    @objc
    private func refreshController(_ sender: Any?) {
      Task { @MainActor [weak self] in await self?.runtimeViewModel.refreshControllerInventory() }
    }
  }

  extension InputTestWindowController: NSToolbarDelegate {
    /// Returns the toolbar items a person may add: Refresh and the flexible space.
    ///
    /// - Parameter toolbar: The toolbar.
    /// - Returns: The toolbar items a person may add: Refresh and the flexible space.
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.refreshIdentifier, .flexibleSpace]
    }

    /// Returns the items the toolbar starts with: the flexible space and Refresh.
    ///
    /// - Parameter toolbar: The toolbar.
    /// - Returns: The items the toolbar starts with: the flexible space and Refresh.
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [.flexibleSpace, Self.refreshIdentifier]
    }

    /// Returns no selectable items.
    ///
    /// - Parameter toolbar: The toolbar.
    /// - Returns: No selectable items.
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    /// Returns the Refresh item, or nil for any other identifier.
    ///
    /// - Parameters:
    ///   - toolbar: The toolbar.
    ///   - itemIdentifier: The identifier of the item.
    ///   - flag: Whether the toolbar inserts the item now.
    /// - Returns: The Refresh item, or nil for any other identifier.
    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      switch itemIdentifier {
      case Self.refreshIdentifier:
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(refreshController(_:))
        item.label = OJDLocalized.string("action.refresh")
        item.paletteLabel = item.label
        item.toolTip = item.label
        item.image = NSImage(
          systemSymbolName: "arrow.clockwise",
          accessibilityDescription: item.label
        )
        return item
      default: return nil
      }
    }
  }

#endif
