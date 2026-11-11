#if canImport(AppKit)

  import Carbon
  import OpenJoystickDriverKit

  /// The pause shortcut registered with the system, which works while another app is in front and
  /// needs no permission.
  @MainActor
  @safe
  final class PauseHotKey {
    /// Carbon refused the registration, for example because another app owns the combination.
    struct RegistrationError: Error, Equatable {
      /// The `OSStatus` that Carbon returned.
      let status: OSStatus
    }

    private static let signature: OSType = 0x4F4A_4450

    private let pressed: @MainActor () -> Void
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Whether a shortcut is registered.
    var isRegistered: Bool { unsafe reference != nil }

    /// Creates the hot key with no shortcut; `pressed` runs on each press.
    init(pressed: @escaping @MainActor () -> Void) { self.pressed = pressed }

    /// The Carbon modifier mask of `modifiers`.
    nonisolated static func carbonModifiers(_ modifiers: Set<PauseShortcut.Modifier>) -> UInt32 {
      modifiers.reduce(0) { mask, modifier in
        switch modifier {
        case .command: return mask | UInt32(cmdKey)
        case .control: return mask | UInt32(controlKey)
        case .option: return mask | UInt32(optionKey)
        case .shift: return mask | UInt32(shiftKey)
        }
      }
    }

    /// Replaces the registered shortcut with `shortcut`, or releases it for nil.
    ///
    /// - Throws: ``RegistrationError`` when the system refuses the combination; the previous
    ///   shortcut is released in that case too.
    func register(_ shortcut: PauseShortcut?) throws {
      if let current = unsafe reference { unsafe UnregisterEventHotKey(current) }
      unsafe reference = nil
      guard let shortcut else { return }
      try installHandler()
      var registered: EventHotKeyRef?
      let status = unsafe RegisterEventHotKey(
        shortcut.keyCode,
        Self.carbonModifiers(shortcut.modifiers),
        EventHotKeyID(signature: Self.signature, id: 1),
        GetApplicationEventTarget(),
        0,
        &registered
      )
      guard status == noErr else { throw RegistrationError(status: status) }
      unsafe reference = registered
    }

    // The handler stays installed for the life of the app, so the context pointer stays valid.
    private func installHandler() throws {
      guard unsafe handler == nil else { return }
      var type = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      )
      let status = unsafe InstallEventHandler(
        GetApplicationEventTarget(),
        { _, _, context in
          guard let pointer = unsafe context else { return OSStatus(eventNotHandledErr) }
          let hotKey = unsafe Unmanaged<PauseHotKey>.fromOpaque(pointer).takeUnretainedValue()
          MainActor.assumeIsolated { hotKey.pressed() }
          return noErr
        },
        1,
        &type,
        unsafe Unmanaged.passUnretained(self).toOpaque(),
        &handler
      )
      guard status == noErr else { throw RegistrationError(status: status) }
    }
  }

  /// The shortcut as the menus show it, such as `⌃⌥P`.
  enum PauseShortcutDisplay {
    private static let glyphs: [(PauseShortcut.Modifier, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    static func text(_ shortcut: PauseShortcut) -> String {
      glyphs.filter { shortcut.modifiers.contains($0.0) }.map(\.1).joined() + shortcut.key
    }
  }

#endif
