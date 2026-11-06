#if canImport(AppKit)

  import AppKit
  import OpenJoystickDriverKit
  import UniformTypeIdentifiers

  /// The save and open panels of the Controllers detail.
  ///
  /// Each opens as a sheet of the key window.
  @MainActor
  enum ControllerFilePanels {
    /// Shows the panel as a sheet of the key window, or as its own window when there is none.
    ///
    /// - Parameters:
    ///   - panel: The panel to show.
    ///   - completion: Receives the response of the person.
    private static func present(
      _ panel: NSSavePanel,
      completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
      if let window = NSApp.keyWindow {
        panel.beginSheetModal(for: window, completionHandler: completion)
      } else {
        panel.begin(completionHandler: completion)
      }
    }

    /// Asks where to save `request`; `completion` gets the chosen file, or nil when cancelled.
    ///
    /// - Parameters:
    ///   - request: The file to save, with its suggested name and folder.
    ///   - completion: Receives the chosen file, or nil when the person cancelled.
    static func save(
      _ request: ControllerDetailActions.SaveRequest,
      completion: @escaping (URL?) -> Void
    ) {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = request.fileName
      panel.canCreateDirectories = true
      if let directory = request.directory { panel.directoryURL = directory }
      present(panel) { completion($0 == .OK ? panel.url : nil) }
    }

    /// Asks where to save the mapping of `profile`, with a format popup as accessory; `completion`
    /// gets the format and file, or nil when cancelled.
    ///
    /// - Parameters:
    ///   - profile: The virtual gamepad profile to export.
    ///   - completion: Receives the format and the file, or nil when the person cancelled.
    static func exportMapping(
      profile: VirtualHIDProfileID,
      completion: @escaping ((format: VirtualMappingFormat, url: URL)?) -> Void
    ) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("ui.controllers.exportMapping.title")
      panel.canCreateDirectories = true
      let accessory = ExportMappingAccessory(panel: panel, profile: profile)
      panel.accessoryView = accessory.view
      present(panel) { response in
        guard response == .OK, let url = panel.url else { return completion(nil) }
        completion((accessory.format, url))
        withExtendedLifetime(accessory) {}
      }
    }

    /// Asks for a program, an app or an executable file, with the SDL backend option as accessory;
    /// `completion` gets the program and the option, or nil when cancelled.
    ///
    /// - Parameter completion: Receives the program and whether the person chose the game
    ///   controller backend, or nil when the person cancelled.
    static func chooseProgram(
      completion: @escaping ((program: URL, gameControllerBackend: Bool)?) -> Void
    ) {
      let panel = NSOpenPanel()
      panel.title = OJDLocalized.string("ui.controllers.launch.title")
      panel.prompt = OJDLocalized.string("ui.controllers.launch.prompt")
      panel.allowedContentTypes = [.application, .unixExecutable]
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      let backend = NSButton(
        checkboxWithTitle: OJDLocalized.string("ui.controllers.launch.gameControllerBackend"),
        target: nil,
        action: nil
      )
      backend.toolTip = OJDLocalized.string(
        "platform.macos.cli.virtual.launch.sdlGamecontrollerBackend"
      )
      backend.sizeToFit()
      panel.accessoryView = backend
      present(panel) { response in
        guard response == .OK, let url = panel.url else { return completion(nil) }
        completion((url, backend.state == .on))
      }
    }
  }

  /// The format popup of the export panel.
  ///
  /// It keeps the suggested file name and type in step with the chosen format.
  @MainActor
  private final class ExportMappingAccessory: NSObject {
    /// The accessory view with the format label and the popup.
    let view: NSView
    /// The popup that lists the formats.
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The panel whose file name and type follow the format.
    private unowned let panel: NSSavePanel
    /// The virtual gamepad profile whose mapping is exported.
    private let profile: VirtualHIDProfileID

    /// Creates the accessory for `panel` and sets the file name and type of the first format.
    ///
    /// - Parameters:
    ///   - panel: The panel that shows the accessory.
    ///   - profile: The virtual gamepad profile to export.
    init(panel: NSSavePanel, profile: VirtualHIDProfileID) {
      self.panel = panel
      self.profile = profile
      let label = NSTextField(
        labelWithString: OJDLocalized.string("ui.controllers.exportMapping.format")
      )
      popup.setAccessibilityTitleUIElement(label)
      let stack = NSStackView(views: [label, popup])
      stack.orientation = .horizontal
      stack.spacing = 8
      stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
      view = stack
      super.init()
      popup.addItems(withTitles: VirtualMappingFormat.allCases.map(\.rawValue))
      popup.target = self
      popup.action = #selector(formatChanged)
      formatChanged()
    }

    /// The format that the popup selects.
    var format: VirtualMappingFormat {
      VirtualMappingFormat.allCases[max(0, popup.indexOfSelectedItem)]
    }

    /// Sets the panel's file name and type to those of the selected format.
    @objc
    private func formatChanged() {
      panel.nameFieldStringValue = VirtualGamepadExport.fileName(format: format, profile: profile)
      panel.allowedContentTypes = [format == .sdl ? .plainText : .json]
    }
  }

#endif
