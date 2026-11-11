public import Foundation

/// The failures of reading or changing the user settings file.
public enum SettingsStoreError: Error, Equatable, LocalizedError, Sendable {
  /// The file is not an XML property list of the `Settings` kind (including an unknown key).
  case damaged(file: String)
  /// The file's `apiVersion` or `kind` is not the supported one; the problem names the file.
  case unsupported(file: String, problem: DocumentHeaderProblem)
  /// The file, or its lock file, cannot be opened or written.
  case unwritable(file: String)
  /// The file could not be moved to the Trash.
  case cannotReset(file: String)
  /// The change would turn off both Show in menu bar and Show in Dock.
  case noVisibleEntryPoint
  /// The file turns off both Show in menu bar and Show in Dock, which leaves no entry point.
  case storedNoVisibleEntryPoint(file: String)

  /// The localization of the error descriptions.
  private static let localization = Localization()

  /// The settings file the error is about; `nil` when the error is about a change, not a file.
  public var file: String? {
    switch self {
    case .damaged(let file), .unsupported(let file, _), .unwritable(let file),
      .cannotReset(let file), .storedNoVisibleEntryPoint(let file):
      file
    case .noVisibleEntryPoint: nil
    }
  }

  /// Whether the file itself cannot be used, so a reset (moving it to the Trash) fixes the error.
  ///
  /// A file that cannot be written or moved is not fixed by a reset.
  public var fileIsUnusable: Bool {
    switch self {
    case .damaged, .unsupported, .storedNoVisibleEntryPoint: true
    case .unwritable, .cannotReset, .noVisibleEntryPoint: false
    }
  }

  /// The description of the error for the user.
  public var errorDescription: String? {
    switch self {
    case .damaged(let file):
      Self.localization.formatted("ui.settings.advanced.errorDamaged", arguments: [file])
    case .unsupported(let file, let problem):
      Self.localization.formatted("ui.settings.advanced.errorUnsupported", arguments: [file])
        + "\n" + problem.description
    case .unwritable(let file):
      Self.localization.formatted("ui.settings.advanced.errorUnwritable", arguments: [file])
    case .cannotReset(let file):
      Self.localization.formatted("ui.settings.advanced.errorCannotReset", arguments: [file])
    case .storedNoVisibleEntryPoint(let file):
      Self.localization.formatted(
        "platform.macos.ui.settings.advanced.errorStoredNoVisibleEntryPoint",
        arguments: [file]
      )
    case .noVisibleEntryPoint:
      Self.localization.string("platform.macos.ui.settings.advanced.errorNoVisibleEntryPoint")
    }
  }
}

/// Reads and writes the `Settings.plist` file through the `DataDirectory` port.
///
/// The layers, lowest to highest precedence:
/// 1. the built-in defaults (``ApplicationSettingKey/defaultValue``);
/// 2. the user file in ``DataLocation/applicationData``, which is the only file OJD writes.
///
/// A missing file is an empty layer. A damaged or unsupported file is an error, never an empty
/// layer, so a mistake does not silently reset settings; ``moveToTrash()`` is the explicit reset.
/// An update holds an advisory lock on a sidecar file while it reads, changes, and writes, so the
/// app, the service, and the CLI cannot lose each other's updates.
public struct SettingsStore: Sendable {
  /// The name of the user settings file.
  public static let fileName = "Settings.plist"
  /// The sidecar file whose advisory lock serializes updates.
  public static let lockFileName = "Settings.plist.lock"
  /// The location whose `Settings.plist` is read and written.
  public static let location = DataLocation.applicationData

  /// The data directory that locates the settings folder.
  private let directory: any DataDirectory
  /// Moves a file to the Trash.
  private let trash: @Sendable (URL) throws -> Void

  /// `trash` moves the settings file to the Trash; the default is the user's Trash.
  @preconcurrency
  public init(
    directory: any DataDirectory = MacOSDataDirectory(),
    trash: @escaping @Sendable (URL) throws -> Void = {
      try unsafe FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }
  ) {
    self.directory = directory
    self.trash = trash
  }

  /// The path of the user file.
  public var userFileURL: URL { directory.fileURL(Self.fileName, in: Self.location) }

  /// The folder that holds the user file.
  public var folderURL: URL { directory.url(for: Self.location) }

  /// The built-in defaults overlaid by the user file.
  public func load() throws -> SettingsDocument {
    try SettingsDocument().overlaid(by: read(userFileURL))
  }

  /// The value of `key` after the user file and the built-in default apply.
  ///
  /// For `launchAtLogin` this is the stored opt-out, not the login item; macOS answers for the
  /// login item (see ``ApplicationServiceManager/isLaunchAtLoginEnabled``).
  public func value(of key: ApplicationSettingKey) throws -> Bool {
    try load()[key] ?? key.defaultValue
  }

  /// Whether the user turned launch at login off, so the app must not register itself again.
  public func launchAtLoginOptOut() throws -> Bool { try load().launchAtLoginOptOut ?? false }

  /// Stores `value` for `key` in the user file.
  public func set(_ key: ApplicationSettingKey, to value: Bool) throws {
    try update([key: value])
  }

  /// Stores every value in `values` in the user file in one write.
  public func update(_ values: [ApplicationSettingKey: Bool]) throws {
    let url = userFileURL
    do {
      try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch { throw SettingsStoreError.unwritable(file: url.path) }
    try locked {
      var document = try read(url)
      for (key, value) in values { document[key] = value }
      if values[.showInMenuBar] != nil || values[.showInDock] != nil,
        document.hasNoVisibleEntryPoint
      {
        throw SettingsStoreError.noVisibleEntryPoint
      }
      do { try DocumentCoder.encode(document).write(to: url, options: .atomic) } catch {
        throw SettingsStoreError.unwritable(file: url.path)
      }
    }
  }

  /// Moves the user file to the Trash, whatever it holds, so the built-in defaults apply again.
  ///
  /// Returns whether there was a file to move.
  @discardableResult
  public func moveToTrash() throws -> Bool {
    let url = userFileURL
    guard FileManager.default.fileExists(atPath: folderURL.path) else { return false }
    return try locked {
      guard FileManager.default.fileExists(atPath: url.path) else { return false }
      do { try trash(url) } catch { throw SettingsStoreError.cannotReset(file: url.path) }
      return true
    }
  }

  /// Runs `body` while holding the advisory lock on the sidecar file in the settings folder.
  private func locked<Result>(_ body: () throws -> Result) throws -> Result {
    let url = userFileURL
    let lock = unsafe open(
      folderURL.appendingPathComponent(Self.lockFileName).path,
      O_CREAT | O_RDWR | O_CLOEXEC,
      0o600
    )
    guard lock >= 0 else { throw SettingsStoreError.unwritable(file: url.path) }
    // Closing the descriptor also releases the lock.
    defer { close(lock) }
    while flock(lock, LOCK_EX) != 0 {
      guard errno == EINTR else { throw SettingsStoreError.unwritable(file: url.path) }
    }
    return try body()
  }

  /// Reads the settings document at `url`; an absent file gives an empty document.
  ///
  /// - Throws: ``SettingsStoreError/storedNoVisibleEntryPoint(file:)`` when the file turns off both
  ///   entry points, ``SettingsStoreError/unsupported(file:problem:)`` for an unsupported header,
  ///   and ``SettingsStoreError/damaged(file:)`` for a file that cannot be read or decoded.
  private func read(_ url: URL) throws -> SettingsDocument {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
      return SettingsDocument()
    } catch { throw SettingsStoreError.damaged(file: url.path) }
    do {
      let document = try DocumentCoder.decode(SettingsDocument.self, from: data, file: url.path)
      if document.hasNoVisibleEntryPoint {
        throw SettingsStoreError.storedNoVisibleEntryPoint(file: url.path)
      }
      return document
    } catch let error as SettingsStoreError {
      throw error
    } catch let problem as SettingsHeaderProblem {
      throw SettingsStoreError.unsupported(
        file: url.path,
        problem: problem.problem.located(in: url.path)
      )
    } catch { throw SettingsStoreError.damaged(file: url.path) }
  }
}
