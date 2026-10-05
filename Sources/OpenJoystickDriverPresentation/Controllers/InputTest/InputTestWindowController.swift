#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  enum InputTestWindowSizingPolicy {
    static let defaultContentSize = NSSize(width: 900, height: 620)
    static let minimumContentSize = NSSize(width: 700, height: 500)

    static func fittingContentSize(_ current: NSSize) -> NSSize {
      NSSize(
        width: max(current.width, minimumContentSize.width),
        height: max(current.height, minimumContentSize.height)
      )
    }
  }

  @MainActor
  final class InputTestWindowController: NSWindowController, NSWindowDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.InputTestToolbar"
    )
    private static let refreshIdentifier = NSToolbarItem.Identifier(
      "OpenJoystickDriver.InputTest.Refresh"
    )

    let model: InputTestViewModel
    private let runtimeViewModel: RuntimeViewModel
    private let visibilityChanged: @MainActor (Bool) -> Void

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

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(device: ApplicationServiceDeviceDescription) {
      model.selectDevice(device)
      window?.title = OJDLocalized.formatted(
        "inputTest.windowTitle",
        device.publishedVirtualProfile?.productName ?? device.name
      )
      model.open()
      visibilityChanged(true)
      if let window { WindowFramePolicy.clamp(window) }
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func stop() { model.close() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      model.close()
      sender.orderOut(nil)
      visibilityChanged(false)
      return false
    }

    private func configureToolbar(for window: NSWindow) {
      let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconAndLabel
      window.toolbar = toolbar
      toolbar.isVisible = true
    }

    @objc
    private func refreshController(_ sender: Any?) {
      Task { @MainActor [weak self] in await self?.runtimeViewModel.refreshControllerInventory() }
    }
  }

  extension InputTestWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.refreshIdentifier, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [.flexibleSpace, Self.refreshIdentifier]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

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
        item.label = OJDLocalized.string("common.refresh")
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
