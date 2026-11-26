#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Native keyboard destination capture

  /// The key control of a keyboard destination: the captured key or No Key, with the Capture Key
  /// and Clear buttons.
  ///
  /// While it captures, the next key press becomes the destination and Escape ends the capture.
  struct KeyboardDestinationCaptureView: View {
    /// The destination that the control shows and sets.
    @Binding
    var destination: RemappingDestination
    /// Whether the destination is cleared, which shows No Key.
    @Binding
    var isCleared: Bool
    /// Whether the control waits for a key press.
    @Binding
    var isCapturing: Bool

    /// The captured key or No Key, with the Capture Key and Clear buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        HStack {
          Group {
            if isCleared {
              Text(OJDLocalized.string("ui.keyboard.noKey"))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            } else {
              KeyboardDestinationLabel(destination: destination)
            }
          }
          Spacer()
          Button(
            isCapturing
              ? OJDLocalized.string("ui.keyboard.pressKey")
              : OJDLocalized.string("ui.keyboard.captureKey")
          ) {
            isCapturing = true
            isCleared = false
            Self.announce(
              OJDLocalized.string(
                "ui.keyboard.captureStarted"
              )
            )
          }.disabled(isCapturing).help(OJDLocalized.string("ui.help.captureKey"))
          Button(OJDLocalized.string("action.clear")) {
            isCapturing = false
            isCleared = true
          }.disabled(isCleared).help(OJDLocalized.string("ui.help.clearKey"))
        }
        if isCapturing {
          Text(
            OJDLocalized.string(
              "ui.keyboard.instructions"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          KeyboardDestinationCaptureRepresentable(
            onCapture: { captured in
              destination = captured
              isCleared = false
              isCapturing = false
              Self.announce(
                OJDLocalized.formatted(
                  "ui.keyboard.captured",
                  RuntimePresentation.destinationLabel(captured)
                )
              )
            },
            onCancel: {
              isCapturing = false
              Self.announce(
                OJDLocalized.string(
                  "ui.keyboard.captureCanceled"
                )
              )
            }
          ).frame(width: 1, height: 1)
        }
      }
    }

    /// Announces `message` to VoiceOver.
    private static func announce(_ message: String) {
      unsafe NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
      )
    }
  }

  /// Hosts ``KeyboardDestinationCaptureNSView`` in SwiftUI.
  struct KeyboardDestinationCaptureRepresentable: NSViewRepresentable {
    /// Called with the destination of the pressed key.
    let onCapture: (RemappingDestination) -> Void
    /// Called when the user presses Escape.
    let onCancel: () -> Void

    /// Creates the view that captures the next key.
    ///
    /// - Returns: The view.
    func makeNSView(context _: Context) -> KeyboardDestinationCaptureNSView {
      KeyboardDestinationCaptureNSView(onCapture: onCapture, onCancel: onCancel)
    }

    /// Gives the view the current callbacks and makes it the first responder.
    ///
    /// - Parameters:
    ///   - nsView: The view that captures the key.
    ///   - _: The context of the representable.
    func updateNSView(_ nsView: KeyboardDestinationCaptureNSView, context _: Context) {
      nsView.onCapture = onCapture
      nsView.onCancel = onCancel
      unsafe nsView.window?.makeFirstResponder(nsView)
    }
  }

  /// Takes keyboard focus and reports the next key press as a keyboard destination.
  final class KeyboardDestinationCaptureNSView: NSView {
    /// Called with the destination of the pressed key.
    var onCapture: (RemappingDestination) -> Void
    /// Called when the user presses Escape.
    var onCancel: () -> Void

    /// Creates the view with the callbacks for a captured key and for Escape.
    init(onCapture: @escaping (RemappingDestination) -> Void, onCancel: @escaping () -> Void) {
      self.onCapture = onCapture
      self.onCancel = onCancel
      super.init(frame: .zero)
      setAccessibilityElement(true)
      setAccessibilityRole(.textField)
      setAccessibilityLabel(
        OJDLocalized.string("ui.keyboard.captureTitle")
      )
    }

    /// Unavailable, because the view is created in code only.
    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      unsafe window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
      // Escape cancels this focused capture, rather than becoming a keyboard destination. The
      // outer sheet monitor receives Escape only once capture has ended and continues to dismiss
      // the whole assignment sheet in that state.
      if event.keyCode == 53 {
        onCancel()
        return
      }
      guard let key = KeyboardDestinationKeyMapper.key(for: event) else {
        NSSound.beep()
        return
      }
      let modifiers = KeyboardDestinationKeyMapper.modifiers(for: event)
      onCapture(.keyboard(key: key, modifiers: modifiers))
    }
  }

  /// Maps key events to the keys and modifiers of keyboard destinations.
  enum KeyboardDestinationKeyMapper {
    /// Returns the key of the event: by its key code, else by its character; nil when it has none.
    static func key(for event: NSEvent) -> RemappingKeyboardKey? {
      key(keyCode: event.keyCode, character: event.charactersIgnoringModifiers?.lowercased().first)
    }

    /// Returns the key of a hardware key code, else of a lowercased character; nil when neither
    /// names a key.
    static func key(keyCode: UInt16, character: Character?) -> RemappingKeyboardKey? {
      if let key = keysByCode[keyCode] { return key }
      if let character {
        if ("a"..."z").contains(character) {
          return RemappingKeyboardKey(rawValue: "Key" + String(character).uppercased())
        }
        if ("0"..."9").contains(character) {
          return RemappingKeyboardKey(rawValue: "Digit" + String(character))
        }
        return keysByCharacter[character]
      }
      return nil
    }

    /// Returns the modifiers held for the event; Command is meta and Option is alt.
    static func modifiers(for event: NSEvent) -> Set<RemappingKeyModifier> {
      var modifiers = Set<RemappingKeyModifier>()
      if event.modifierFlags.contains(.command) { modifiers.insert(.meta) }
      if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
      if event.modifierFlags.contains(.option) { modifiers.insert(.alt) }
      if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
      return modifiers
    }

    /// The key of each hardware key code that has one.
    private static let keysByCode: [UInt16: RemappingKeyboardKey] = [
      36: .returnKey,
      48: .tab,
      49: .space,
      51: .deleteBackward,
      53: .escape,
      57: .capsLock,
      10: .section,
      110: .insert,
      114: .help,
      117: .deleteForward,
      115: .home,
      119: .end,
      116: .pageUp,
      121: .pageDown,
      123: .arrowLeft,
      124: .arrowRight,
      125: .arrowDown,
      126: .arrowUp,
      122: .f1,
      120: .f2,
      99: .f3,
      118: .f4,
      96: .f5,
      97: .f6,
      98: .f7,
      100: .f8,
      101: .f9,
      109: .f10,
      103: .f11,
      111: .f12,
      105: .f13,
      107: .f14,
      113: .f15,
      106: .f16,
      64: .f17,
      79: .f18,
      80: .f19,
      90: .f20,
      82: .keypad0,
      83: .keypad1,
      84: .keypad2,
      85: .keypad3,
      86: .keypad4,
      87: .keypad5,
      88: .keypad6,
      89: .keypad7,
      91: .keypad8,
      92: .keypad9,
      65: .keypadDecimal,
      67: .keypadMultiply,
      69: .keypadPlus,
      71: .keypadClear,
      75: .keypadDivide,
      76: .keypadEnter,
      78: .keypadMinus,
      81: .keypadEqual,
    ]

    /// The key of each punctuation or space character.
    private static let keysByCharacter: [Character: RemappingKeyboardKey] = [
      " ": .space,
      "-": .minus,
      "=": .equal,
      "[": .leftBracket,
      "]": .rightBracket,
      "\\": .backslash,
      ";": .semicolon,
      "'": .quote,
      ",": .comma,
      ".": .period,
      "/": .slash,
      "`": .grave,
    ]
  }

  /// Calls `onEscape` when Escape is pressed, unless a key capture runs and handles Escape itself.
  struct EscapeKeyMonitor: NSViewRepresentable {
    /// Returns whether a key capture runs.
    let isCapturing: () -> Bool
    /// Called when Escape is pressed outside a key capture.
    let onEscape: () -> Void

    /// Creates the view that monitors the Escape key.
    ///
    /// - Returns: The view.
    func makeNSView(context _: Context) -> EscapeKeyMonitorNSView {
      EscapeKeyMonitorNSView(isCapturing: isCapturing, onEscape: onEscape)
    }

    /// Gives the view the current callbacks.
    ///
    /// - Parameters:
    ///   - nsView: The view that monitors the key.
    ///   - _: The context of the representable.
    func updateNSView(_ nsView: EscapeKeyMonitorNSView, context _: Context) {
      nsView.isCapturing = isCapturing
      nsView.onEscape = onEscape
    }

    /// Stops the monitor of the view when SwiftUI removes it.
    ///
    /// - Parameters:
    ///   - nsView: The view that monitors the key.
    ///   - _: The coordinator, which is not used.
    static func dismantleNSView(_ nsView: EscapeKeyMonitorNSView, coordinator _: ()) {
      nsView.stopMonitoring()
    }
  }

  /// Watches the key presses of the app and reports Escape.
  final class EscapeKeyMonitorNSView: NSView {
    /// Returns whether a key capture runs.
    var isCapturing: () -> Bool
    /// Called when Escape is pressed outside a key capture.
    var onEscape: () -> Void
    /// The local key down monitor, or nil while monitoring is stopped.
    private var eventMonitor: Any?

    /// Creates the view and starts monitoring.
    init(isCapturing: @escaping () -> Bool, onEscape: @escaping () -> Void) {
      self.isCapturing = isCapturing
      self.onEscape = onEscape
      super.init(frame: .zero)
      startMonitoring()
    }

    /// Unavailable, because the view is created in code only.
    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if unsafe window == nil { stopMonitoring() } else { startMonitoring() }
    }

    /// Starts the key down monitor; does nothing while it runs.
    ///
    /// Escape reaches `onEscape` and is consumed, unless a key capture runs.
    func startMonitoring() {
      guard eventMonitor == nil else { return }
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.keyCode == 53 else { return event }
        guard !(self?.isCapturing() ?? false) else { return event }
        self?.onEscape()
        return nil
      }
    }

    /// Removes the key down monitor.
    func stopMonitoring() {
      if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
      eventMonitor = nil
    }

  }

#endif
