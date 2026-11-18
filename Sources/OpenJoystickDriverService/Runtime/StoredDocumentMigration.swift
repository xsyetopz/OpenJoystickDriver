import Foundation
import OpenJoystickDriverKit

/// Converts the stored documents of an earlier alpha when the service starts.
///
/// It runs before any reader opens a store, so a reader never meets a stale file the migration can
/// convert. A file that fails stays unchanged and its reader refuses it as before.
enum StoredDocumentMigration {
  /// Migrates the support folder of `directory` and passes `log` one line per scanned file.
  @discardableResult
  static func run(
    directory: any DataDirectory = MacOSDataDirectory(),
    log: (String) -> Void
  ) -> [DocumentMigrator.Entry] {
    let entries = DocumentMigrator(directory: directory).run(dryRun: false)
    for entry in entries {
      let reason = entry.detail.map { ": \($0)" } ?? ""
      log("[Migrate] \(entry.verdict.rawValue) \(entry.file)\(reason)")
    }
    return entries
  }
}
