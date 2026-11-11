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
          }.disabled(isCapturing)
          Button(OJDLocalized.string("action.clear")) {
            isCapturing = false
            isCleared = true
          }.disabled(isCleared)
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
  private enum KeyboardDestinationKeyMapper {
    /// Returns the key of the event: by its key code, else by its character; nil when it has none.
    static func key(for event: NSEvent) -> RemappingKeyboardKey? {
      if let key = keyCodeMap(event.keyCode) { return key }
      if let character = event.charactersIgnoringModifiers?.lowercased().first {
        if ("a"..."z").contains(character) {
          return RemappingKeyboardKey(rawValue: "Key" + String(character).uppercased())
        }
        if ("0"..."9").contains(character) {
          return RemappingKeyboardKey(rawValue: "Digit" + String(character))
        }
        switch character {
        case " ": return .space
        case "-": return .minus
        case "=": return .equal
        case "[": return .leftBracket
        case "]": return .rightBracket
        case "\\": return .backslash
        case ";": return .semicolon
        case "'": return .quote
        case ",": return .comma
        case ".": return .period
        case "/": return .slash
        case "`": return .grave
        default: break
        }
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

    /// Returns the key of a hardware key code, or nil for a code without a key.
    private static func keyCodeMap(_ keyCode: UInt16) -> RemappingKeyboardKey? {
      switch keyCode {
      case 36: return .returnKey
      case 48: return .tab
      case 49: return .space
      case 51: return .deleteBackward
      case 53: return .escape
      case 57: return .capsLock
      case 10: return .section
      case 110: return .insert
      case 114: return .help
      case 117: return .deleteForward
      case 115: return .home
      case 119: return .end
      case 116: return .pageUp
      case 121: return .pageDown
      case 123: return .arrowLeft
      case 124: return .arrowRight
      case 125: return .arrowDown
      case 126: return .arrowUp
      case 122: return .f1
      case 120: return .f2
      case 99: return .f3
      case 118: return .f4
      case 96: return .f5
      case 97: return .f6
      case 98: return .f7
      case 100: return .f8
      case 101: return .f9
      case 109: return .f10
      case 103: return .f11
      case 111: return .f12
      case 105: return .f13
      case 107: return .f14
      case 113: return .f15
      case 106: return .f16
      case 64: return .f17
      case 79: return .f18
      case 80: return .f19
      case 90: return .f20
      case 82: return .keypad0
      case 83: return .keypad1
      case 84: return .keypad2
      case 85: return .keypad3
      case 86: return .keypad4
      case 87: return .keypad5
      case 88: return .keypad6
      case 89: return .keypad7
      case 91: return .keypad8
      case 92: return .keypad9
      case 65: return .keypadDecimal
      case 67: return .keypadMultiply
      case 69: return .keypadPlus
      case 71: return .keypadClear
      case 75: return .keypadDivide
      case 76: return .keypadEnter
      case 78: return .keypadMinus
      case 81: return .keypadEqual
      default: return nil
      }
    }
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
