import Foundation

/// The tier at which a database line matched a pad's GUID.
///
/// The tiers are SDL's, tried in order: the version with the exact name CRC, the version with no
/// CRC, no version with the exact CRC, then neither.
public enum SDLMatchTier: String, CaseIterable, Codable, Sendable {
  /// The line's GUID is the pad's.
  case exactGUID = "ExactGUID"
  /// The line's GUID is the pad's with the name CRC bytes zeroed.
  case guidWithoutNameCRC = "GUIDWithoutNameCRC"
  /// The line's GUID is the pad's with the version bytes zeroed.
  case guidWithoutVersion = "GUIDWithoutVersion"
  /// The line's GUID is the pad's with the name CRC and version bytes zeroed.
  case guidWithoutVersionAndNameCRC = "GUIDWithoutVersionAndNameCRC"
}

/// A line of the database that matched a pad.
struct SDLDatabaseMatch: Equatable, Sendable {
  /// The GUID the line is written under.
  let guid: SDLGUID
  /// The tier at which it matched.
  let tier: SDLMatchTier
  /// The line's name field.
  let name: String
  /// The line's mapping fields, as written: `key:binding` pairs.
  let fields: [String]
}

/// A line of the database that is not a comment, blank, or well-formed.
struct SDLDatabaseProblem: Error, Equatable, CustomStringConvertible {
  /// The 1-based line number.
  let lineNumber: Int
  /// Why the line is malformed.
  let description: String
}

/// SDL_GameControllerDB lines, indexed by GUID.
struct SDLGameControllerDatabase: Sendable {
  /// A line's name and fields.
  private struct Line: Sendable {
    /// The controller name.
    let name: String
    /// The `key:binding` fields, in line order.
    let fields: [String]
  }

  /// The lines by GUID; when a GUID has several lines, the last wins.
  private let lines: [SDLGUID: Line]

  /// The text of the database shipped in the bundle.
  static let bundledText: String = {
    guard let url = Bundle.module.url(forResource: "sdl-gamecontrollerdb", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { fatalError("[SDLGameControllerDatabase] The bundled database is missing") }
    return text
  }()

  /// The database shipped in the bundle.
  static let bundled: Self = {
    guard let database = try? Self(text: bundledText) else {
      fatalError("[SDLGameControllerDatabase] The bundled database is malformed")
    }
    return database
  }()

  /// Parses `text`: `#` comment lines and blank lines are skipped; every other line is
  /// `GUID,name,key:binding,...` with a 32-digit GUID and a trailing comma allowed.
  ///
  /// Throws ``SDLDatabaseProblem`` for the first malformed line.
  init(text: String) throws {
    var parsed: [SDLGUID: Line] = [:]
    for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      var parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      if parts.last?.isEmpty == true { parts.removeLast() }
      guard parts.count >= 3, let guid = SDLGUID(parts[0]) else {
        throw SDLDatabaseProblem(
          lineNumber: index + 1,
          description: "a line needs a 32-digit GUID, a name and at least one field"
        )
      }
      parsed[guid] = Line(name: parts[1], fields: Array(parts[2...]))
    }
    self.lines = parsed
  }

  /// The line for `guid` at the first tier that has one.
  func match(_ guid: SDLGUID) -> SDLDatabaseMatch? {
    let tiers: [(SDLGUID, SDLMatchTier)] = [
      (guid, .exactGUID),
      (guid.withoutNameCRC, .guidWithoutNameCRC),
      (guid.withoutVersion, .guidWithoutVersion),
      (guid.withoutVersion.withoutNameCRC, .guidWithoutVersionAndNameCRC),
    ]
    for (candidate, tier) in tiers {
      if let line = lines[candidate] {
        return SDLDatabaseMatch(guid: candidate, tier: tier, name: line.name, fields: line.fields)
      }
    }
    return nil
  }
}
