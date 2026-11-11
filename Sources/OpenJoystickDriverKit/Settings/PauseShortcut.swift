import Foundation

/// The text of a pause shortcut is not modifiers joined by `+` and a key name.
public struct PauseShortcutError: Error, Equatable, Sendable {
  /// The text that was refused.
  public let text: String
}

/// The system-wide keyboard shortcut that pauses and resumes every controller: a key and the
/// modifier keys held with it.
///
/// See `pauseShortcut` in `Resources/Schemas/settings.schema.json`.
public struct PauseShortcut: Equatable, Sendable {
  /// A modifier key, named as in the schema.
  public enum Modifier: String, CaseIterable, Codable, Sendable {
    /// The Command key.
    case command
    /// The Control key.
    case control
    /// The Option key.
    case option
    /// The Shift key.
    case shift
  }

  /// The key names with their ANSI virtual key codes, in schema order.
  private static let keys: [(name: String, code: UInt32)] = [
    ("A", 0x00), ("B", 0x0B), ("C", 0x08), ("D", 0x02), ("E", 0x0E), ("F", 0x03), ("G", 0x05),
    ("H", 0x04), ("I", 0x22), ("J", 0x26), ("K", 0x28), ("L", 0x25), ("M", 0x2E), ("N", 0x2D),
    ("O", 0x1F), ("P", 0x23), ("Q", 0x0C), ("R", 0x0F), ("S", 0x01), ("T", 0x11), ("U", 0x20),
    ("V", 0x09), ("W", 0x0D), ("X", 0x07), ("Y", 0x10), ("Z", 0x06),
    ("0", 0x1D), ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15), ("5", 0x17), ("6", 0x16),
    ("7", 0x1A), ("8", 0x1C), ("9", 0x19),
    ("F1", 0x7A), ("F2", 0x78), ("F3", 0x63), ("F4", 0x76), ("F5", 0x60), ("F6", 0x61),
    ("F7", 0x62), ("F8", 0x64), ("F9", 0x65), ("F10", 0x6D), ("F11", 0x67), ("F12", 0x6F),
    ("Space", 0x31),
  ]

  /// Every key name a shortcut accepts.
  public static let keyNames = keys.map(\.name)

  /// The virtual key code of `name`, one of ``keyNames``.
  public static func keyCode(of name: String) -> UInt32 {
    keys.first { $0.name == name }!.code
  }

  /// The key name, one of ``keyNames``.
  public let key: String
  /// The modifier keys held with the key; at least one is not Shift.
  public let modifiers: Set<Modifier>

  /// Creates a shortcut from a key name and its modifiers.
  ///
  /// - Throws: ``PauseShortcutError`` for an unknown key, or when no modifier other than Shift
  ///   is held, because a shortcut without one would capture ordinary typing.
  public init(key: String, modifiers: Set<Modifier>) throws {
    guard Self.keyNames.contains(key), !modifiers.subtracting([.shift]).isEmpty else {
      throw PauseShortcutError(text: key)
    }
    self.key = key
    self.modifiers = modifiers
  }

  /// Parses modifiers and a key joined by `+`, such as `control+option+P`; case does not matter.
  public init(parsing text: String) throws {
    let parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let last = parts.last,
      let key = Self.keyNames.first(where: { $0.caseInsensitiveCompare(last) == .orderedSame })
    else { throw PauseShortcutError(text: text) }
    let modifiers = try parts.dropLast().map {
      guard let modifier = Modifier(rawValue: $0.lowercased()) else {
        throw PauseShortcutError(text: text)
      }
      return modifier
    }
    guard Set(modifiers).count == modifiers.count else { throw PauseShortcutError(text: text) }
    do { try self.init(key: key, modifiers: Set(modifiers)) } catch {
      throw PauseShortcutError(text: text)
    }
  }

  /// The virtual key code of the key.
  public var keyCode: UInt32 { Self.keyCode(of: key) }

  /// The modifiers in schema order.
  private var sortedModifiers: [Modifier] { Modifier.allCases.filter(modifiers.contains) }

  /// The shortcut as `control+option+P`, which ``init(parsing:)`` reads back.
  public var text: String { (sortedModifiers.map(\.rawValue) + [key]).joined(separator: "+") }
}

extension PauseShortcut: Codable {
  /// The keys of the stored shortcut.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The key and its modifiers.
    case key, modifiers
  }

  /// Decodes the stored shortcut; an unknown key, a repeated or missing modifier, or a shortcut
  /// with no modifier other than Shift is refused.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let modifiers = try container.decode([Modifier].self, forKey: .modifiers)
    guard Set(modifiers).count == modifiers.count else {
      throw DecodingError.dataCorruptedError(
        forKey: .modifiers,
        in: container,
        debugDescription: "repeated modifier"
      )
    }
    do {
      try self.init(key: container.decode(String.self, forKey: .key), modifiers: Set(modifiers))
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .key,
        in: container,
        debugDescription: "not a pause shortcut"
      )
    }
  }

  /// Encodes the key and the modifiers in schema order.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(key, forKey: .key)
    try container.encode(sortedModifiers, forKey: .modifiers)
  }
}
