import Foundation
import OpenJoystickDriverKit

/// A failure of a library operation: the message to show and the error code `ojd explain` knows.
struct LibraryFailure: Error, Equatable {
  /// What went wrong, in words.
  let message: String
  /// The error code that `ojd explain` knows, or nil when the failure has none.
  let code: ErrorCode?
}

/// A controller record: a bundled one, or one that a user file or an installed package adds or
/// patches.
struct LibraryRecordItem: Equatable, Identifiable {
  /// The controller the record describes.
  let model: ControllerModelID
  /// The protocol family of the controller.
  let family: PhysicalProtocolID
  /// The layer that provides the record.
  let layer: ControllerRecordLayer
  /// The record's file, or nil for a bundled record.
  let file: URL?
  /// The file name of the user file or mod file that patches a built-in record.
  var patchedBy: String?
  /// Whether the Apple-signed USB extension claims the controller.
  var appleSigned = false

  /// The row's gray line: the family, the layer, and the Apple-signed text for a controller the
  /// signed USB extension claims.
  ///
  /// A bundled record leaves out its layer, because only the Built-in scope lists it and the scope
  /// switch already says Built-in.
  var subtitle: String {
    var segments = [family.displayName]
    if layer != .bundled { segments.append(layer.libraryTitle) }
    if appleSigned { segments.append(Self.appleSignedText) }
    return segments.dropFirst().reduce(segments[0]) {
      OJDLocalized.formatted("ui.library.record.detail", $0, $1)
    }
  }

  /// The text of a record whose controller the signed USB extension claims.
  private static var appleSignedText: String {
    OJDLocalized.string("platform.macos.ui.library.record.appleSigned")
  }

  /// The model, which identifies the record.
  var id: ControllerModelID { model }
  /// The record's vendor and product ID as `VVVV:PPPP`.
  var identity: String { model.description }
  /// Only a record that a user file adds or patches can be removed here; a package's record
  /// goes with its package.
  var isRemovable: Bool { layer == .user }
  /// The record's file as the Library shows it, with the home folder written as `~`.
  var fileDisplayPath: String? { file.map { HomeFolder.redacting($0.path) } }

  /// Whether the record's `VVVV:PPPP`, its family's display name or its family's `ojd` token, or
  /// the Apple-signed text of a controller the signed USB extension claims, contains `query`,
  /// ignoring case, so a search finds what the Library shows and what `ojd` prints.
  ///
  /// An empty query matches every record.
  func matches(_ query: String) -> Bool {
    Self.contains(
      query,
      in: [identity, family.displayName, family.commandLineName]
        + (appleSigned ? [Self.appleSignedText] : [])
    )
  }

  /// Returns whether any of `fields` contains `query`, ignoring case and surrounding spaces.
  ///
  /// An empty query matches.
  static func contains(_ query: String, in fields: [String]) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty
      || fields.contains { $0.range(of: trimmed, options: .caseInsensitive) != nil }
  }
}
