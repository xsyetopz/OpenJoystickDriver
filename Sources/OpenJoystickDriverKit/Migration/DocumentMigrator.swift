import Foundation

/// Converts the stored documents of an older `apiVersion` to the current one.
///
/// This is the one place that applies ``DocumentMigrationStep``; the readers stay single-version
/// and refuse a stale document. A document is converted only when the user runs it. Installed mods
/// are not touched.
public struct DocumentMigrator: Sendable {
  /// What happened to one document.
  public enum Status: String, Codable, Equatable, Sendable {
    /// The document was converted and its original kept.
    case converted
    /// A dry run found a document it would convert.
    case wouldConvert
    /// The document was not converted and is unchanged.
    case failed
  }

  /// One stale document.
  public struct Entry: Codable, Equatable, Sendable {
    /// The path of the document in the support folder, such as `Profiles/<id>.json`.
    public let file: String
    /// The `kind` of the document.
    public let kind: String
    /// What happened to it.
    public let status: Status
    /// Why the document failed, for ``Status/failed``.
    public let detail: String?
  }

  /// The name of the folder of the support folder that holds the kept originals.
  public static let backupFolderName = "Migrated"

  /// The data directory that locates the support folder.
  private let directory: any DataDirectory

  /// Creates a migrator for the support folder of `directory`.
  public init(directory: any DataDirectory = MacOSDataDirectory()) { self.directory = directory }

  /// The folder of the kept originals.
  public var backupDirectory: URL {
    directory.url(for: .applicationData)
      .appendingPathComponent(Self.backupFolderName, isDirectory: true)
  }

  /// Converts every stale document, or only lists them when `dryRun` is set.
  ///
  /// A document that cannot be converted, or whose converted form its current reader refuses, is
  /// a ``Status/failed`` entry and stays unchanged; the others are still converted. The result is
  /// sorted by path.
  public func run(dryRun: Bool) -> [Entry] {
    let root = directory.url(for: .applicationData)
    var entries: [Entry] = []
    for (folder, kinds) in Self.places {
      for url in files(in: folder.isEmpty ? root : root.appendingPathComponent(folder)) {
        let file = folder.isEmpty ? url.lastPathComponent : "\(folder)/\(url.lastPathComponent)"
        guard let data = try? Data(contentsOf: url),
          let document = try? OrderedJSON.parse(data),
          let version = document["apiVersion"]?.string, version != OpenJoystickDriverAPI.version,
          let kind = document["kind"]?.string.flatMap(DocumentKind.init(rawValue:)),
          kinds.contains(kind)
        else { continue }
        do {
          let converted = try convert(document, kind: kind, file: url)
          if !dryRun { try write(converted, to: url, as: file) }
          let status: Status = dryRun ? .wouldConvert : .converted
          entries.append(Entry(file: file, kind: kind.rawValue, status: status, detail: nil))
        } catch {
          entries.append(
            Entry(file: file, kind: kind.rawValue, status: .failed, detail: "\(error)")
          )
        }
      }
    }
    return entries.sorted { $0.file < $1.file }
  }

  /// The folders of the support folder that hold stored documents, with the kinds each holds.
  private static let places: [(String, Set<DocumentKind>)] = [
    ("", [.settings, .accessGrants]),
    ("Profiles", [.profile]),
    ("Controllers", [.controller, .controllerPatch]),
    (VirtualHIDProfileOverrideStore.directoryName, [.virtualDevice]),
  ]

  /// The `.json` files directly in `folder`, without the lock and backup files.
  private func files(in folder: URL) -> [URL] {
    let urls = try? FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    return (urls ?? []).filter { $0.pathExtension == "json" }
  }

  /// The document converted by the chain of steps, checked with its current reader.
  private func convert(_ document: OrderedJSON, kind: DocumentKind, file: URL) throws -> Data {
    var converted = document
    while let version = converted["apiVersion"]?.string, version != OpenJoystickDriverAPI.version {
      guard
        let step = DocumentMigrationStep.all.first(where: {
          $0.kind == kind.rawValue && $0.from == version
        })
      else { throw DocumentMigrationProblem("no conversion from \(version)") }
      converted = try step.convert(converted)
    }
    let data = converted.formattedData()
    try Self.check(data, kind: kind, file: file)
    return data
  }

  /// Throws what the current reader of `kind` throws for `data`.
  ///
  /// The reader of `AccessGrants.json` is in the service target, so only its header and object
  /// shape are checked here.
  private static func check(_ data: Data, kind: DocumentKind, file: URL) throws {
    switch kind {
    case .settings: _ = try JSONDecoder().decode(SettingsDocument.self, from: data)
    case .profile: _ = try JSONDecoder().decode(RemappingProfile.self, from: data)
    case .controller, .controllerPatch:
      let isAll = file.lastPathComponent == "all.patch.json"
      let layer: ControllerRecordLayer = isAll ? .global : .user
      _ = try ControllerRecordSet.parse(data, file: file, layer: layer)
    case .virtualDevice:
      let source = VirtualDevice.Source.file(file.lastPathComponent)
      _ = try VirtualDevice.decode(data, source: source, requiresMatch: true)
    case .accessGrants:
      let document = try OrderedJSON.parse(data)
      if let problem = OpenJoystickDriverAPI.headerProblem(
        apiVersion: document["apiVersion"]?.string,
        kind: document["kind"]?.string,
        expected: kind.rawValue
      ) {
        throw problem
      }
    }
  }

  /// Keeps the original of `file` in the backup folder, then replaces it with `data`.
  ///
  /// A backup that exists already is not overwritten, so a second run cannot lose an original.
  private func write(_ data: Data, to url: URL, as file: String) throws {
    let backup = backupDirectory.appendingPathComponent(file)
    guard !FileManager.default.fileExists(atPath: backup.path) else {
      throw DocumentMigrationProblem("\(Self.backupFolderName)/\(file) exists already")
    }
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
    try FileManager.default.createDirectory(
      at: backup.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: url, to: backup)
    try data.write(to: url, options: .atomic)
    if let permissions {
      try FileManager.default.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: url.path
      )
    }
  }
}
