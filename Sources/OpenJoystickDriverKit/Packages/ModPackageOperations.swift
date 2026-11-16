public import Foundation

/// One installed package in `ojd mod list --json`, the endpoint `Mods` line, and the Shortcuts
/// action. `problem` is why the package is not used.
public struct ModPackageEntry: Encodable, Equatable, Sendable {
  /// The package name.
  public let name: String
  /// The package version.
  public let version: String?
  /// The package author.
  public let author: String?
  /// The files the package installs.
  public let files: [String]
  /// Why OJD does not use the package, or nil when it does.
  public let problem: String?

  /// Describes `package`.
  public init(_ package: ModPackage) {
    name = package.name
    version = package.manifest?.version
    author = package.manifest?.author
    files = package.manifest.map(\.listedFiles) ?? []
    problem = package.problem
  }
}

/// What ``ModPackageStore/installPackage(from:replace:dryRun:)`` did, or would do with `dryRun`.
public struct ModPackageInstallation: Equatable, Sendable {
  /// The folder of the package in the store.
  public let destination: URL
  /// Whether a package of the same name was installed before.
  public let replaced: Bool
  /// The manifest of the package.
  public let manifest: ModPackageManifest
}

extension ModPackageStore {
  /// The failure that reports `error` with its E4xxx code, for `ojd mod`, the endpoint, and the
  /// App Intents.
  public static func failure(_ error: ModPackageError, subject: String) -> CodedFailure {
    CodedFailure(
      error.code,
      Localization().formatted("cli.mod.group.refused", arguments: [subject, error.detail])
    )
  }

  /// Every folder of the store as an entry.
  public func entries() -> [ModPackageEntry] { list().map(ModPackageEntry.init) }

  /// Checks the package in `folder` and installs it, as `ojd mod install` does.
  ///
  /// Validation never depends on `replace`, so `requires` and clashes always refuse. With `dryRun`
  /// nothing is written.
  ///
  /// - Throws: ``CodedFailure`` with the E4xxx code of the refusal, or
  ///   ``ErrorCode/packageAlreadyInstalled`` when a package of the name is installed and `replace`
  ///   is false.
  @discardableResult
  public func installPackage(
    from folder: URL,
    replace: Bool = false,
    dryRun: Bool = false
  ) throws -> ModPackageInstallation {
    do {
      let manifest = try validate(folder)
      let destination = directory.appendingPathComponent(manifest.name, isDirectory: true)
      let replaced = (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil
      if replaced, !replace {
        throw CodedFailure(
          .packageAlreadyInstalled,
          Localization().formatted("cli.mod.group.alreadyInstalled", arguments: [manifest.name])
        )
      }
      if !dryRun { try install(folder, replace: replace) }
      return ModPackageInstallation(
        destination: destination,
        replaced: replaced,
        manifest: manifest
      )
    } catch let error as ModPackageError {
      throw Self.failure(error, subject: folder.path)
    }
  }

  /// Removes the installed package `name`, as `ojd mod remove --force` does, and returns its
  /// folder.
  ///
  /// With `dryRun` nothing is removed.
  ///
  /// - Throws: ``CodedFailure`` with ``ErrorCode/packageNotInstalled`` when the store has no
  ///   package of that name, or the E4xxx code of a failed removal.
  @discardableResult
  public func removePackage(named name: String, dryRun: Bool = false) throws -> URL {
    let target = directory.appendingPathComponent(name, isDirectory: true)
    // The name rules of `remove(_:)`, checked first so a missing package is E4006 in every mode.
    let named = !name.isEmpty && !name.hasPrefix(".") && !name.contains("/")
    guard named, (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil else {
      throw CodedFailure(
        .packageNotInstalled,
        Localization().formatted("cli.mod.group.notInstalled", arguments: [name])
      )
    }
    do { if !dryRun { try remove(name) } } catch let error as ModPackageError {
      throw Self.failure(error, subject: name)
    }
    return target
  }
}
