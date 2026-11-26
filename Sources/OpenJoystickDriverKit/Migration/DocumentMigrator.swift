public import Foundation

/// Converts the stored documents of an older `apiVersion` to the current one.
///
/// This is the one place that applies a ``DocumentUpgrade``; the readers stay single-version
/// and refuse a stale document. Every file it scans gets one ``Verdict``.
public struct DocumentMigrator: Sendable {
  /// What became of one file.
  public enum Verdict: String, Codable, Equatable, Sendable {
    /// The file was converted and its original kept, or a dry run found it would be.
    case migrated = "Migrated"
    /// The file is already in the current format.
    case current = "Current"
    /// The file could not be converted and is unchanged.
    case failed = "Failed"
    /// The file is not a document of OpenJoystickDriver and is unchanged.
    case foreign = "Foreign"
  }

  /// One scanned file.
  public struct Entry: Codable, Equatable, Sendable {
    /// The path of the file below the scanned folder, such as `Profiles/<id>.json`.
    public let file: String
    /// The `kind` of the document, when the file has one.
    public let kind: String?
    /// What became of it.
    public let verdict: Verdict
    /// Why the file failed or is foreign.
    public let detail: String?
  }

  /// The name of the folder that holds the kept originals, in the scanned folder.
  public static let backupFolderName = "Migrated"

  /// The reason a store lists for a `.json` document that no reader loads.
  public static let staleProblem = "E5001: saved by an earlier version; migrate it"

  /// The kind that names `ActiveProfiles`, a root array without a header.
  static let activeProfilesKind = "ActiveProfiles"

  /// The kind that names `LastUsed.plist`, the headerless profile activation times.
  ///
  /// The service keeps them as a root dictionary that has had one form since it was added, so the
  /// file is never converted.
  static let lastUsedKind = "LastUsed"

  /// The path of the activation times below the support folder.
  static let lastUsedFile = "LastUsed.plist"

  /// The data directory that locates the support folder.
  private let directory: any DataDirectory

  /// Creates a migrator for the support folder of `directory`.
  public init(directory: any DataDirectory = MacOSDataDirectory()) { self.directory = directory }

  /// The folder of the kept originals of the support folder.
  public var backupDirectory: URL {
    directory.url(for: .applicationData)
      .appendingPathComponent(Self.backupFolderName, isDirectory: true)
  }

  /// Scans the support folder, or `folder` and everything below it, and converts every stale
  /// document, or only reports them when `dryRun` is set.
  ///
  /// A file that cannot be converted, or whose converted form its current reader refuses, is a
  /// ``Verdict/failed`` entry and stays unchanged; the others are still converted. The result is
  /// sorted by path.
  public func run(dryRun: Bool, folder: URL? = nil) -> [Entry] {
    let root = (folder ?? directory.url(for: .applicationData)).resolvingSymlinksInPath()
    let backups = root.appendingPathComponent(Self.backupFolderName, isDirectory: true)
    let urls = folder == nil ? Self.storeFiles(in: root) : Self.allFiles(in: root)
    return
      urls
      .map { url in
        let file = String(url.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
        return entry(url, file: file, backups: backups, dryRun: dryRun)
      }
      .sorted { $0.file < $1.file }
  }

  /// The folders of the support folder that hold stored documents; the last is read recursively.
  private static let storeFolders = [
    "Profiles", "Controllers", VirtualHIDProfileOverrideStore.directoryName,
    VirtualHIDProfileOverrideStore.unreadFolderName,
  ]

  /// The files of the support folder that can be documents.
  private static func storeFiles(in root: URL) -> [URL] {
    let own = storeFolders.flatMap { files(in: root.appendingPathComponent($0), deep: false) }
    return files(in: root, deep: false) + own
      + files(in: root.appendingPathComponent("Packages"), deep: true)
  }

  /// Every file below `root` that can be a document, without the backup folder.
  private static func allFiles(in root: URL) -> [URL] {
    files(in: root, deep: true).filter {
      !$0.resolvingSymlinksInPath().path.hasPrefix(
        root.appendingPathComponent(backupFolderName).path + "/"
      )
    }
  }

  /// The `.json` and `.plist` files of `folder`, and below it when `deep`.
  private static func files(in folder: URL, deep: Bool) -> [URL] {
    let manager = FileManager.default
    let urls: [URL]
    if deep {
      let walk = manager.enumerator(
        at: folder,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      urls = walk?.compactMap { $0 as? URL } ?? []
    } else {
      urls =
        (try? manager.contentsOfDirectory(
          at: folder,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )) ?? []
    }
    return urls.filter { ["json", "plist"].contains($0.pathExtension) }
  }

  /// The verdict for one file.
  private func entry(_ url: URL, file: String, backups: URL, dryRun: Bool) -> Entry {
    func entry(_ kind: String?, _ verdict: Verdict, _ detail: String? = nil) -> Entry {
      Entry(file: file, kind: kind, verdict: verdict, detail: detail)
    }
    guard let data = try? Data(contentsOf: url) else {
      return entry(nil, .failed, "cannot be read")
    }
    let isPlist = url.pathExtension == "plist"
    guard
      let document = isPlist
        ? try? OrderedJSON(document: data, file: file) : try? OrderedJSON.parse(data)
    else { return entry(nil, .foreign, "is not a readable document") }
    return verdict(
      of: document,
      url,
      file: file,
      isPlist: isPlist,
      backups: backups,
      dryRun: dryRun
    )
  }

  /// The verdict for the readable `document` of one file.
  private func verdict(
    of document: OrderedJSON,
    _ url: URL,
    file: String,
    isPlist: Bool,
    backups: URL,
    dryRun: Bool
  ) -> Entry {
    func entry(_ kind: String?, _ verdict: Verdict, _ detail: String? = nil) -> Entry {
      Entry(file: file, kind: kind, verdict: verdict, detail: detail)
    }
    let isActiveProfiles = url.deletingPathExtension().lastPathComponent == "ActiveProfiles"
    if isActiveProfiles, case .array = document {
      guard !isPlist else { return entry(Self.activeProfilesKind, .current) }
      return migrate(
        url,
        file: file,
        kind: Self.activeProfilesKind,
        backups: backups,
        dryRun: dryRun
      ) {
        try V1Alpha2ToV1Alpha3.activeProfiles(document).plistData()
      }
    }
    if file == Self.lastUsedFile, isPlist, case .object = document {
      return entry(Self.lastUsedKind, .current)
    }
    guard let version = document["apiVersion"]?.string else {
      return Self.isRelease05(document, name: url.lastPathComponent)
        ? entry(nil, .failed, "written by 0.5; re-create it")
        : entry(nil, .failed, "has no apiVersion")
    }
    guard version.hasPrefix(DocumentVersion.prefix) else {
      return entry(nil, .foreign, "has another apiVersion")
    }
    guard let kind = document["kind"]?.string.flatMap(DocumentKind.init(rawValue:)) else {
      return entry(nil, .failed, "has an unknown kind")
    }
    if isPlist, version == OpenJoystickDriverAPI.version { return entry(kind.rawValue, .current) }
    let target = url.deletingPathExtension().appendingPathExtension("plist")
    return migrate(url, file: file, kind: kind.rawValue, backups: backups, dryRun: dryRun) {
      try convert(document, kind: kind, file: target)
    }
  }

  /// Whether `document`, a file without an `apiVersion`, is what OJD 0.5 wrote.
  private static func isRelease05(_ document: OrderedJSON, name: String) -> Bool {
    name == "RemappingProfiles.json" || document["$schema"] != nil || document["operation"] != nil
  }

  /// Converts with `make`, and writes the result unless `dryRun`.
  ///
  /// A `.json` file becomes the `.plist` beside it; a `.plist` file is rewritten in place. Either
  /// way the original is kept in the backup folder.
  private func migrate(
    _ url: URL,
    file: String,
    kind: String,
    backups: URL,
    dryRun: Bool,
    make: () throws -> Data
  ) -> Entry {
    let target = url.deletingPathExtension().appendingPathExtension("plist")
    do {
      guard target.path == url.path || !FileManager.default.fileExists(atPath: target.path) else {
        throw DocumentMigrationProblem("\(target.lastPathComponent) exists already")
      }
      let data = try make()
      if !dryRun {
        try write(data, from: url, to: target, backup: backups.appendingPathComponent(file))
      }
      return Entry(file: file, kind: kind, verdict: .migrated, detail: nil)
    } catch {
      return Entry(file: file, kind: kind, verdict: .failed, detail: "\(error)")
    }
  }

  /// The document converted to the current version, checked with its current reader.
  private func convert(_ document: OrderedJSON, kind: DocumentKind, file: URL) throws -> Data {
    let text = document["apiVersion"]?.string ?? ""
    guard let version = DocumentVersion(rawValue: text) else {
      throw DocumentMigrationProblem("no conversion from \(text)")
    }
    let data = try version.migrate(document, kind: kind).plistData()
    try Self.check(data, kind: kind, file: file)
    return data
  }

  /// Throws what the current reader of `kind` throws for `data`.
  ///
  /// The reader of `AccessGrants.json` is in the service target, so only its header and object
  /// shape are checked here.
  private static func check(_ data: Data, kind: DocumentKind, file: URL) throws {
    switch kind {
    case .settings:
      _ = try DocumentCoder.decode(SettingsDocument.self, from: data, file: file.lastPathComponent)
    case .profile: _ = try RemappingProfileFileStore.load(from: data, file: file.lastPathComponent)
    case .modPackage: _ = try ModPackageManifest.parse(data)
    case .controller, .controllerPatch:
      let isAll = file.lastPathComponent == "all.patch.plist"
      let layer: ControllerRecordLayer = isAll ? .global : .user
      _ = try ControllerRecordSet.parse(data, file: file, layer: layer)
    case .virtualDevice:
      let source = VirtualDevice.Source.file(file.lastPathComponent)
      _ = try VirtualDevice.decode(data, source: source, requiresMatch: true)
    case .accessGrants:
      let document = try OrderedJSON(document: data, file: file.lastPathComponent)
      if let problem = OpenJoystickDriverAPI.headerProblem(
        apiVersion: document["apiVersion"]?.string,
        kind: document["kind"]?.string,
        expected: kind.rawValue
      ) {
        throw problem
      }
    }
  }

  /// Keeps the original at `backup`, writes `data` to `target`, and removes the original unless
  /// `target` is the original.
  ///
  /// A backup that exists already is not overwritten, so a second run cannot lose an original.
  private func write(_ data: Data, from url: URL, to target: URL, backup: URL) throws {
    guard !FileManager.default.fileExists(atPath: backup.path) else {
      throw DocumentMigrationProblem(
        "\(Self.backupFolderName)/\(backup.lastPathComponent) exists already"
      )
    }
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
    try FileManager.default.createDirectory(
      at: backup.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: url, to: backup)
    try data.write(to: target, options: .atomic)
    if let permissions {
      try FileManager.default.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: target.path
      )
    }
    if target.path != url.path { try FileManager.default.removeItem(at: url) }
  }
}
