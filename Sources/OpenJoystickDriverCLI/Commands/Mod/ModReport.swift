import Foundation
import OpenJoystickDriverKit

/// Where `ojd mod` reads and writes installed packages.
enum ModStore {
  /// The package store; tests replace it.
  @TaskLocal
  static var directory = ModPackageStore.rootDirectory

  /// The OJD version that a package's `requires` is checked against; tests replace it.
  @TaskLocal
  static var runningVersion: String?

  /// The package store at ``directory``.
  static var store: ModPackageStore {
    ModPackageStore(directory: directory, runningVersion: runningVersion)
  }

  /// The folder named by the `FOLDER` operand.
  static func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

  /// The failure that reports `error` with its E4xxx code.
  static func failure(_ error: ModPackageError, subject: String) -> CLIFailure {
    ModPackageStore.failure(error, subject: subject)
  }
}

/// The `--json` result of `mod validate`, and the `package` of `mod install`.
struct ModPackageValidation: Encodable, Equatable {
  /// Whether the package is accepted.
  let valid: Bool
  /// Why the package is refused.
  let problem: String?
  /// The E4xxx or E5001 code of the refusal.
  let code: String?
  /// The package name.
  let name: String?
  /// The package version.
  let version: String?
  /// The package author.
  let author: String?
  /// The files the package lists.
  let files: [String]?

  /// Describes an accepted package.
  init(_ manifest: ModPackageManifest) {
    valid = true
    problem = nil
    code = nil
    name = manifest.name
    version = manifest.version
    author = manifest.author
    files = manifest.listedFiles
  }

  /// Describes the refusal `error`.
  init(_ error: ModPackageError) {
    valid = false
    problem = error.detail
    code = error.code.rawValue
    name = nil
    version = nil
    author = nil
    files = nil
  }

  /// Validates `folder`.
  ///
  /// A refused package prints `valid: false` with `--json` and fails with the E4xxx code of the
  /// refusal.
  ///
  /// - Throws: ``CLIFailure`` with the code of the refusal.
  static func check(_ folder: String) throws -> ModPackageManifest {
    do { return try ModStore.store.validate(ModStore.folder(folder)) } catch let error
      as ModPackageError
    {
      if CLIContext.current.format == .json { try CLIOutput.json(Self(error)) }
      throw ModStore.failure(error, subject: folder)
    }
  }
}
