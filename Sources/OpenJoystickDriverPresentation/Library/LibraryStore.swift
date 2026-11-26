import Foundation
import OpenJoystickDriverKit

/// The controller records and mod packages the Library area lists, validates, installs and removes.
///
/// The operations are those of `ojd record` and `ojd mod`.
protocol LibraryStore: Sendable {
  /// Loads the records and lists them by scope.
  func records() -> LibraryRecordListing
  /// Returns the full record of `model` from the latest load, or nil when it is not in it.
  func recordDetail(_ model: ControllerModelID) -> LibraryRecordDetail?
  /// Replays the capture through the record's parser and compares the state with the
  /// expectation.
  ///
  /// - Parameters:
  ///   - model: The record to test.
  ///   - capture: The packet capture, as JSON lines.
  ///   - captureName: The name that labels the capture in a failure.
  ///   - expectation: The expected state, as JSON.
  ///   - expectationName: The name that labels the expectation in a failure.
  /// - Returns: The result, which lists any differences.
  /// - Throws: ``LibraryFailure`` when the record is not loaded or a file cannot be read as its
  ///   kind.
  func testRecord(
    _ model: ControllerModelID,
    capture: Data,
    captureName: String,
    expectation: Data,
    expectationName: String
  ) throws -> ControllerRecordTestResult
  /// Validates a record file.
  ///
  /// - Throws: ``LibraryFailure`` with the validation problem and its error code.
  func checkRecord(_ data: Data) throws -> LibraryRecordCheck
  /// Validates a record file and writes it to the record directory.
  ///
  /// - Throws: ``LibraryFailure`` when the file fails validation or cannot be written.
  func installRecord(_ data: Data) throws -> LibraryRecordCheck
  /// Removes the user's files for `model` from the record directory.
  ///
  /// - Throws: ``LibraryFailure`` when no file exists or one cannot be removed.
  func removeRecord(_ model: ControllerModelID) throws
  /// Lists the installed mod packages.
  func installedMods() -> [LibraryModItem]
  /// Validates a mod package folder.
  ///
  /// - Throws: ``LibraryFailure`` when the package is refused.
  func checkMod(folder: URL) throws -> LibraryModCheck
  /// Installs the mod package in `folder`; `replace` allows an installed package of the same
  /// name to be replaced.
  ///
  /// - Throws: ``LibraryFailure`` when the package is refused.
  func installMod(folder: URL, replace: Bool) throws
  /// Removes the installed mod package called `name`.
  ///
  /// - Throws: ``LibraryFailure`` when the package cannot be removed.
  func removeMod(name: String) throws
}
