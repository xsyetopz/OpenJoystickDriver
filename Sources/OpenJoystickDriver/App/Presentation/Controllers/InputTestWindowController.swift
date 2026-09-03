#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  @MainActor final class InputTestWindowController: NSWindowController, NSWindowDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.InputTestToolbar"
    )
    private static let startStopIdentifier = NSToolbarItem.Identifier(
      "OpenJoystickDriver.InputTest.StartStop"
    )
    private static let refreshIdentifier = NSToolbarItem.Identifier(
      "OpenJoystickDriver.InputTest.Refresh"
    )

    let model: InputTestViewModel
    private let runtimeViewModel: RuntimeViewModel
    private var stateObservation: AnyCancellable?

    init(runtime: any InputTestDeviceGateway, runtimeViewModel: RuntimeViewModel) {
      model = InputTestViewModel(gateway: runtime)
      self.runtimeViewModel = runtimeViewModel
      let rootView = InputTestView(model: model, runtimeViewModel: runtimeViewModel)
      let host = NSHostingView(rootView: rootView)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 540),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.contentMinSize = NSSize(width: 800, height: 500)
      window.hidesOnDeactivate = false
      window.setFrameAutosaveName("InputTestWindowGeometryV2")
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.center()
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
      stateObservation = model.$sessionState.sink { [weak self] state in
        self?.updateToolbar(for: state)
      }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func show(device: ApplicationServiceDeviceDescription) {
      model.selectDevice(device)
      window?.title = OJDLocalized.formatted(
        "inputTest.windowTitle",
        fallback: "Input Test — %@",
        device.name
      )
      updateToolbar(for: model.sessionState)
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func stop() { model.close() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      model.close()
      sender.orderOut(nil)
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

    private func updateToolbar(for state: InputTestViewModel.SessionState) {
      guard
        let item = window?.toolbar?.items.first(where: {
          $0.itemIdentifier == Self.startStopIdentifier
        })
      else { return }
      let running: Bool
      switch state {
      case .starting, .live, .stale: running = true
      case .idle, .disconnected, .permissionRequired, .unavailable, .error: running = false
      }
      item.label =
        running
        ? OJDLocalized.string("common.stop", fallback: "Stop")
        : OJDLocalized.string("inputTest.start", fallback: "Start Input Test")
      item.toolTip = item.label
      item.isEnabled = model.device != nil && state != .disconnected && state != .permissionRequired
      if #available(macOS 11.0, *) {
        item.image = NSImage(
          systemSymbolName: running ? "stop.fill" : "play.fill",
          accessibilityDescription: item.label
        )
      }
    }

    @objc private func toggleSampling(_ sender: Any?) {
      if model.isSampling { model.stop() } else { model.start() }
    }

    @objc private func refreshController(_ sender: Any?) {
      Task { @MainActor [weak self] in await self?.runtimeViewModel.refreshControllerInventory() }
    }
  }

  extension InputTestWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.startStopIdentifier, Self.refreshIdentifier, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.startStopIdentifier, .flexibleSpace, Self.refreshIdentifier]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      switch itemIdentifier {
      case Self.startStopIdentifier:
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(toggleSampling(_:))
        item.paletteLabel = OJDLocalized.string("inputTest.start", fallback: "Start Input Test")
        return item
      case Self.refreshIdentifier:
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(refreshController(_:))
        item.label = OJDLocalized.string("common.refresh", fallback: "Refresh Controller")
        item.paletteLabel = item.label
        item.toolTip = item.label
        if #available(macOS 11.0, *) {
          item.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: item.label
          )
        }
        return item
      default: return nil
      }
    }
  }

#endif
