import Foundation

/// The SDL mapping of one persona in a `--json` result.
public struct VirtualSDLReport: Encodable, Equatable, Sendable {
  /// The SDL GUID of the persona.
  public let guid: String
  /// The SDL mapping line of the persona.
  public let mapping: String
  /// False when SDL does not recognize the persona with its default hints.
  public let worksWithDefaultSDLHints: Bool

  /// Creates the report of `mapping`.
  public init(_ mapping: VirtualGamepadMapping) {
    guid = mapping.guid
    worksWithDefaultSDLHints = mapping.worksWithDefaultSDLHints
    self.mapping = mapping.sdlMapping
  }
}

/// The W3C Gamepad description of one persona in a `--json` result: for each index of the standard
/// layout, the control and the input of the virtual gamepad that supplies it.
public struct VirtualW3CReport: Encodable, Equatable, Sendable {
  /// One control of the standard layout.
  public struct Entry: Encodable, Equatable, Sendable {
    /// The index in the standard layout.
    public let index: Int
    /// The name of the control.
    public let control: String
    /// The input of the virtual gamepad that supplies the control.
    public let source: String

    /// Creates the entry of `entry`.
    public init(_ entry: VirtualGamepadMapping.W3CEntry) {
      index = entry.index
      control = entry.control.rawValue
      source = entry.source
    }
  }

  /// The browser id of the persona.
  public let id: String
  /// The buttons, ascending by index.
  public let buttons: [Entry]
  /// The axes, ascending by index.
  public let axes: [Entry]

  /// Creates the report of `mapping`.
  public init(_ mapping: VirtualGamepadMapping) {
    id = mapping.w3cID
    buttons = mapping.w3cButtons.map(Entry.init)
    axes = mapping.w3cAxes.map(Entry.init)
  }
}

/// The formats a virtual gamepad mapping is exported in.
public enum VirtualMappingFormat: String, CaseIterable, Sendable {
  /// SDL mapping lines.
  case sdl = "SDL"
  /// The W3C Gamepad description, as JSON.
  case w3c = "W3C"

  /// The extension of a file that holds the document: SDL mapping lines are text, the W3C
  /// description is JSON.
  public var fileExtension: String {
    switch self {
    case .sdl: "txt"
    case .w3c: "json"
    }
  }

  /// The exported text for `profiles`.
  ///
  /// SDL is one mapping line per profile, which is a valid SDL mapping file; a profile that does
  /// not work with SDL's default hints gets a comment line above its mapping from `hintsNote`. W3C
  /// is one JSON array of the descriptions.
  ///
  /// - Throws: ``VirtualGamepadMappingError`` when the descriptor of a profile does not parse.
  public func document(
    for profiles: [VirtualHIDProfileID],
    hintsNote: (VirtualHIDProfileID) -> String
  ) throws -> String {
    let mappings = try profiles.map { ($0, try $0.gamepadMapping()) }
    switch self {
    case .sdl:
      return mappings.flatMap { profile, mapping -> [String] in
        let note = mapping.worksWithDefaultSDLHints ? [] : ["# \(hintsNote(profile))"]
        return note + [mapping.sdlMapping]
      }.joined(separator: "\n")
    case .w3c:
      struct Description: Encodable {
        let profile: String
        let id: String
        let buttons: [VirtualW3CReport.Entry]
        let axes: [VirtualW3CReport.Entry]
      }
      let descriptions = mappings.map { profile, mapping -> Description in
        let report = VirtualW3CReport(mapping)
        return Description(
          profile: profile.rawValue,
          id: report.id,
          buttons: report.buttons,
          axes: report.axes
        )
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      return String(bytes: try encoder.encode(descriptions), encoding: .utf8) ?? ""
    }
  }
}
