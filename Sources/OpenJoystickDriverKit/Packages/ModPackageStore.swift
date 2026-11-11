import Foundation

/// One folder of the package store: its manifest, and why the package cannot be used.
public struct ModPackage: Equatable, Sendable {
  /// The package folder.
  public let directory: URL
  /// Nil when `mod.plist` is missing or invalid.
  public let manifest: ModPackageManifest?
  /// Why the package cannot be used, or nil when it can.
  ///
  /// A package whose `requires` does not admit the running version keeps its manifest and has
  /// this E4002 problem.
  public let problem: String?

  /// The folder name, which is the package name.
  public var name: String { directory.lastPathComponent }
}

/// The installed mod packages: `<AppSupport>/OpenJoystickDriver/Packages/<name>/`.
///
/// A package is a folder with a `mod.plist` manifest and `Controllers/`, `Profiles/`,
/// `VirtualDevices/`, and `Protocols/` folders. The store checks a package against the running version, its own
/// files, and the user's files and the other installed packages before it installs the package.
/// Each refusal is a ``ModPackageError`` with an E4xxx code.
public struct ModPackageStore: Sendable {
  /// `~/Library/Application Support/OpenJoystickDriver/Packages`.
  public static var rootDirectory: URL { directory(besides: ControllerRecordSet.userDirectory) }

  /// The package store beside a user `Controllers` directory, such as the one a test passes.
  public static func directory(besides controllers: URL) -> URL {
    controllers.deletingLastPathComponent().appendingPathComponent("Packages", isDirectory: true)
  }

  /// The folder of the store.
  let directory: URL
  /// The OJD version that a package's `requires` is checked against.
  let runningVersion: String

  /// A store in `directory`.
  ///
  /// The user's own files are in the folders beside it. `runningVersion` is the OJD version that a
  /// package's `requires` is checked against.
  public init(directory: URL = Self.rootDirectory, runningVersion: String? = nil) {
    self.directory = directory
    self.runningVersion = runningVersion ?? ApplicationVersion.current
  }

  /// Every folder of the store in name order, with the packages that cannot be used included.
  ///
  /// A package whose `requires` does not admit the running version gets the E4002 problem. A
  /// running version that is not a SemVer version is a development build, which admits every
  /// package here; ``validate(_:)`` and ``install(_:replace:)`` still refuse it.
  public func list() -> [ModPackage] {
    let folders =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    return folders.filter {
      (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { folder in
      do {
        let manifest = try Self.manifest(in: folder)
        guard manifest.name == folder.lastPathComponent else {
          throw ModPackageError(
            .invalidManifest,
            "\(ModPackageManifest.fileName) names the package \(manifest.name), but the "
              + "folder is \(folder.lastPathComponent)"
          )
        }
        let excluded = SemanticVersion(runningVersion) == nil ? nil : requiresProblem(of: manifest)
        return ModPackage(directory: folder, manifest: manifest, problem: excluded.map { "\($0)" })
      } catch {
        return ModPackage(directory: folder, manifest: nil, problem: "\(error)")
      }
    }
  }

  /// Installs the package in `folder`, and returns it as installed.
  ///
  /// The package is copied into a hidden staging folder of the store, without hidden files and
  /// scripts, and without following links, and the copy is validated and then swapped in at once. So the
  /// installed files are the validated ones even when `folder` changes during the install, and a
  /// failed install leaves the installed package intact and no staging folder behind.
  ///
  /// The service reloads when the store folder changes, which an install, a replace, and a
  /// remove do. A file that is edited in place inside an installed package does not change the
  /// store folder, so the service does not reload for it until the next change.
  ///
  /// - Parameters:
  ///   - folder: The folder of the package to install.
  ///   - replace: Replaces an installed package of the same name. It does not override a
  ///     clash or `requires`.
  /// - Returns: The package as installed.
  /// - Throws: ``ModPackageError``. A package file that cannot be read is E4003. A failure to
  ///   create the store or the staging folder, or to swap the package in, is E4007.
  @discardableResult
  public func install(_ folder: URL, replace: Bool = false) throws -> ModPackage {
    let manager = FileManager.default
    guard !Self.isLink(folder) else {
      throw ModPackageError(.invalidPackageContent, "\(folder.lastPathComponent) is a link")
    }
    try Self.write("the package store cannot be created") {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let staged = directory.appendingPathComponent(".staging.\(UUID().uuidString)")
    do {
      try Self.write("the package cannot be staged") {
        try manager.createDirectory(at: staged, withIntermediateDirectories: false)
      }
      do { try Self.copy(folder, to: staged) } catch let error as ModPackageError {
        throw error
      } catch {
        throw ModPackageError(
          .invalidPackageContent,
          "the package cannot be read: \(error.localizedDescription)"
        )
      }
      let manifest = try validate(staged)
      let installed = directory.appendingPathComponent(manifest.name, isDirectory: true)
      let present = Self.entryExists(installed)
      if present && !replace {
        throw ModPackageError(.packageAlreadyInstalled, "\(manifest.name) is already installed")
      }
      try Self.write("\(manifest.name) cannot be put in the package store") {
        if present && Self.isDirectory(installed) {
          _ = try manager.replaceItemAt(installed, withItemAt: staged)
        } else {
          // A link or file in the place of the folder, such as a dangling link, is removed
          // itself.
          if present { try manager.removeItem(at: installed) }
          try manager.moveItem(at: staged, to: installed)
        }
      }
      return ModPackage(directory: installed, manifest: manifest, problem: nil)
    } catch {
      try? manager.removeItem(at: staged)
      throw error
    }
  }

  /// Removes the installed package called `name`.
  ///
  /// A link in the place of the folder is removed, and not what it points to.
  ///
  /// - Throws: ``ModPackageError`` with ``ErrorCode/packageNotInstalled`` when no entry of the
  ///   store has this name. A name with a path separator, or one that starts with a dot, names
  ///   none. ``ErrorCode/packageStoreUnwritable`` when the entry cannot be removed.
  public func remove(_ name: String) throws {
    let installed = directory.appendingPathComponent(name, isDirectory: true)
    guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), Self.entryExists(installed)
    else { throw ModPackageError(.packageNotInstalled, "\(name) is not installed") }
    try Self.write("\(name) cannot be removed") {
      try FileManager.default.removeItem(at: installed)
    }
  }

  /// Runs `body`, a write to the store, and reports its failure as E4007 with `failure` and the
  /// file system's reason.
  private static func write(_ failure: String, _ body: () throws -> Void) throws {
    do { try body() } catch {
      throw ModPackageError(
        .packageStoreUnwritable,
        "\(failure): \(error.localizedDescription)"
      )
    }
  }

  /// Whether `url` is an entry of its folder, a dangling link included.
  private static func entryExists(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
  }

  /// Whether `url` is itself a symbolic link.
  static func isLink(_ url: URL) -> Bool { fileType(url) == .typeSymbolicLink }

  /// Whether `url` is itself a directory.
  static func isDirectory(_ url: URL) -> Bool { fileType(url) == .typeDirectory }

  /// The type of the entry itself, which is not the type of what a link points to.
  private static func fileType(_ url: URL) -> FileAttributeType? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.type] as? FileAttributeType
  }

  /// Copies the folder `source` into `destination`, which is created when it does not exist,
  /// without hidden files and scripts.
  ///
  /// A link is refused, so that nothing outside the package is read.
  private static func copy(_ source: URL, to destination: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: destination, withIntermediateDirectories: true)
    for entry in try manager.contentsOfDirectory(
      at: source,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) where !isScript(entry) {
      let target = destination.appendingPathComponent(entry.lastPathComponent)
      if isLink(entry) {
        throw ModPackageError(.invalidPackageContent, "\(entry.lastPathComponent) is a link")
      }
      if isDirectory(entry) {
        try copy(entry, to: target)
      } else {
        try manager.copyItem(at: entry, to: target)
      }
    }
  }

  /// The manifest of the package in `folder`.
  ///
  /// - Throws: ``ModPackageError`` with ``ErrorCode/invalidManifest`` when `mod.plist` is missing or
  ///   invalid.
  static func manifest(in folder: URL) throws -> ModPackageManifest {
    let file = folder.appendingPathComponent(ModPackageManifest.fileName)
    guard let data = try? Data(contentsOf: file) else {
      throw ModPackageError(.invalidManifest, "\(ModPackageManifest.fileName) is missing")
    }
    return try ModPackageManifest.parse(data)
  }
}
