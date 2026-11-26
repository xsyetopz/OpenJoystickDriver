import Foundation
import OpenJoystickDriverKit

/// A file in the record directory that OJD skipped, and why.
struct LibrarySkippedFile: Equatable, Identifiable {
  /// The path of the skipped file.
  let path: String
  /// Why OJD skipped the file, in words.
  let problem: String

  /// The path, which identifies the file.
  var id: String { path }
  /// Whether the file is a stale `.json` document that Migrate converts.
  var offersMigration: Bool { problem == DocumentMigrator.staleProblem }
  /// The path as the Library shows it, with the home folder written as `~`.
  var displayPath: String { HomeFolder.redacting(path) }
}

/// The records of the Library area, grouped by scope.
struct LibraryRecordListing: Equatable {
  /// The effective records that a user file or a package adds or patches, by model.
  var installed: [LibraryRecordItem] = []
  /// The whole bundled catalog, as `ojd record list --bundled` lists it, by model.
  var builtIn: [LibraryRecordItem] = []
  /// The files in the record directory that OJD skipped.
  var skipped: [LibrarySkippedFile] = []
}

/// A top-level field of a record and the layer that sets it.
struct LibraryRecordField: Equatable, Identifiable {
  /// The name of the field.
  let name: String
  /// The layer that sets the field.
  let layer: ControllerRecordLayer

  /// The name, which identifies the field.
  var id: String { name }
}

/// Everything `ojd record show` prints for one record.
struct LibraryRecordDetail: Equatable {
  /// The record in the list.
  let item: LibraryRecordItem
  /// How OJD reaches the controller: `HID` or `USB`.
  let transport: String
  /// Why OJD reaches the controller only in a limited way, in words.
  let notes: [String]
  /// Whether the signed USB extension claims the controller; nil for a family without raw USB.
  let claimedByUSBExtension: Bool?
  /// The top-level fields of the record, with the layer that sets each.
  let fields: [LibraryRecordField]
  /// The effective record as colored property list text.
  let record: LibraryRecordDocument
}

/// A record test run.
struct LibraryTestRun: Equatable {
  /// The record that the capture was replayed through.
  let model: ControllerModelID
  /// The name of the expectation file.
  let expectation: String
  /// What the replay found.
  let result: ControllerRecordTestResult
}

/// The identity and file name of a record file that passed validation.
struct LibraryRecordCheck: Equatable {
  /// The record's vendor and product ID as `VVVV:PPPP`, or the selector of a patch.
  let identity: String
  /// The file name that the record is stored under.
  let fileName: String
  /// Whether the record directory already holds a file of this name.
  let replaces: Bool
}

/// A mod package in the Library list.
struct LibraryModItem: Equatable, Identifiable {
  /// The package name.
  let name: String
  /// The version in the manifest, or nil.
  let version: String?
  /// The author in the manifest, or nil.
  let author: String?
  /// The files the manifest lists.
  let files: [String]
  /// Why the package is not used, or nil when it is.
  let problem: String?

  /// The name, which identifies the package.
  var id: String { name }

  /// Whether the mod's name contains `query`, ignoring case.
  ///
  /// An empty query matches every mod.
  func matches(_ query: String) -> Bool { LibraryRecordItem.contains(query, in: [name]) }
}

/// The name, version, author and files of a mod package folder that passed validation.
struct LibraryModCheck: Equatable {
  /// The package name.
  let name: String
  /// The version in the manifest.
  let version: String
  /// The author in the manifest.
  let author: String
  /// The files the manifest lists.
  let files: [String]
  /// Whether a package of this name is installed.
  let replaces: Bool
}
