#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Native keyboard destination capture

  struct KeyboardDestinationCaptureView: View {
    @Binding var destination: RemappingDestination
    @Binding var isCleared: Bool
    @Binding var isCapturing: Bool

    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Group {
            if isCleared {
              Text(OJDLocalized.string("keyboard.noKey", fallback: "No key selected"))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            } else {
              KeyboardDestinationLabel(destination: destination)
            }
          }
          Spacer()
          Button(
            isCapturing
              ? OJDLocalized.string("keyboard.pressKey", fallback: "Press a key...")
              : OJDLocalized.string("keyboard.captureKey", fallback: "Capture key")
          ) {
            isCapturing = true
            isCleared = false
            Self.announce(
              OJDLocalized.string(
                "keyboard.captureStarted",
                fallback: "Keyboard capture started. Press a key; press Escape to cancel."
              )
            )
          }.disabled(isCapturing)
          Button(OJDLocalized.string("common.clear", fallback: "Clear")) {
            isCapturing = false
            isCleared = true
          }.disabled(isCleared)
        }
        if isCapturing {
          Text(
            OJDLocalized.string(
              "keyboard.instructions",
              fallback: "Press a key with any modifiers you want to preserve."
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          KeyboardDestinationCaptureRepresentable(
            onCapture: { captured in
              destination = captured
              isCleared = false
              isCapturing = false
              Self.announce(
                OJDLocalized.formatted(
                  "keyboard.captured",
                  fallback: "Captured %@.",
                  RuntimePresentation.destinationLabel(captured)
                )
              )
            },
            onCancel: {
              isCapturing = false
              Self.announce(
                OJDLocalized.string(
                  "keyboard.captureCanceled",
                  fallback: "Keyboard capture canceled."
                )
              )
            }
          ).frame(width: 1, height: 1)
        }
      }
    }

    private static func announce(_ message: String) {
      NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
      )
    }
  }

  struct KeyboardDestinationCaptureRepresentable: NSViewRepresentable {
    let onCapture: (RemappingDestination) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyboardDestinationCaptureNSView {
      KeyboardDestinationCaptureNSView(onCapture: onCapture, onCancel: onCancel)
    }

    func updateNSView(_ nsView: KeyboardDestinationCaptureNSView, context: Context) {
      nsView.onCapture = onCapture
      nsView.onCancel = onCancel
      nsView.window?.makeFirstResponder(nsView)
    }
  }

  final class KeyboardDestinationCaptureNSView: NSView {
    var onCapture: (RemappingDestination) -> Void
    var onCancel: () -> Void

    init(onCapture: @escaping (RemappingDestination) -> Void, onCancel: @escaping () -> Void) {
      self.onCapture = onCapture
      self.onCancel = onCancel
      super.init(frame: .zero)
      setAccessibilityElement(true)
      setAccessibilityRole(.textField)
      setAccessibilityLabel(
        OJDLocalized.string("keyboard.captureTitle", fallback: "Keyboard key capture")
      )
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.makeFirstResponder(self)
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

  private enum KeyboardDestinationKeyMapper {
    static func key(for event: NSEvent) -> RemappingKeyboardKey? {
      if let key = keyCodeMap(event.keyCode) { return key }
      if let character = event.charactersIgnoringModifiers?.lowercased().first {
        if ("a"..."z").contains(character) {
          return RemappingKeyboardKey(rawValue: String(character))
        }
        if ("0"..."9").contains(character) {
          return RemappingKeyboardKey(rawValue: String(character))
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

    static func modifiers(for event: NSEvent) -> Set<RemappingKeyModifier> {
      var modifiers = Set<RemappingKeyModifier>()
      if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
      if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
      if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
      if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
      return modifiers
    }

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

  struct EscapeKeyMonitor: NSViewRepresentable {
    let isCapturing: () -> Bool
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeKeyMonitorNSView {
      EscapeKeyMonitorNSView(isCapturing: isCapturing, onEscape: onEscape)
    }

    func updateNSView(_ nsView: EscapeKeyMonitorNSView, context: Context) {
      nsView.isCapturing = isCapturing
      nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: EscapeKeyMonitorNSView, coordinator: ()) {
      nsView.stopMonitoring()
    }
  }

  final class EscapeKeyMonitorNSView: NSView {
    var isCapturing: () -> Bool
    var onEscape: () -> Void
    private var eventMonitor: Any?

    init(isCapturing: @escaping () -> Bool, onEscape: @escaping () -> Void) {
      self.isCapturing = isCapturing
      self.onEscape = onEscape
      super.init(frame: .zero)
      startMonitoring()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { stopMonitoring() } else { startMonitoring() }
    }

    func startMonitoring() {
      guard eventMonitor == nil else { return }
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.keyCode == 53 else { return event }
        guard !(self?.isCapturing() ?? false) else { return event }
        self?.onEscape()
        return nil
      }
    }

    func stopMonitoring() {
      if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
      eventMonitor = nil
    }

  }

#endif
