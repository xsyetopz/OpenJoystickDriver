import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {
  /// A file the library could not use, with the bytes it read so recovery acts on that content.
  enum RecoveryIssue: Equatable, Sendable {
    case damagedProfile(fileName: String, data: Data)
    case unusableLibrary(data: Data)
  }

  /// Replaces the issues, keeping the identifier of each issue that was already reported.
  func setIssues(_ issues: [RecoveryIssue]) {
    var previous = profileIssues
    var current: [UUID: RecoveryIssue] = [:]
    for issue in issues {
      let id = previous.first { $0.value == issue }?.key ?? UUID()
      previous[id] = nil
      current[id] = issue
    }
    profileIssues = current
  }

  /// Backs up and deletes a damaged profile file.
  @discardableResult
  func deleteDamagedProfile(issueID: UUID) throws -> RemappingProfileMutationImpact {
    _ = try loadIfNeeded()
    guard case .damagedProfile(let fileName, let data) = profileIssues[issueID] else {
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
    let url = profilesDirectory.appendingPathComponent(fileName, isDirectory: false)
    try requireCurrentData(data, at: url, issueID: issueID)
    try backUp(data, of: url)
    do { try FileManager.default.removeItem(at: url) } catch {
      throw RemappingProfileLibraryError.unwritableLibrary
    }
    profileIssues[issueID] = nil
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [])
  }

  /// Backs up unreadable selections and replaces them with none. The profiles are kept.
  @discardableResult
  func resetDamagedLibrary(issueID: UUID) throws -> RemappingProfileMutationImpact {
    _ = try loadIfNeeded()
    guard case .unusableLibrary(let data) = profileIssues[issueID] else {
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
    try requireCurrentData(data, at: selectionsURL, issueID: issueID)
    try backUp(data, of: selectionsURL)
    do { try Self.writePrivate(Data("[]".utf8), to: selectionsURL) } catch {
      throw RemappingProfileLibraryError.unwritableLibrary
    }
    profileIssues[issueID] = nil
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [])
  }

  /// Discards the cached library and reads the files again.
  ///
  /// Returns the models whose active profiles, resolved to their content, changed.
  func reload() throws -> Set<RemappingProfileModel> {
    let previous = library.map(Self.resolvedSelections) ?? [:]
    library = nil
    let current = Self.resolvedSelections(try loadIfNeeded())
    return Set(previous.keys).union(current.keys).filter { previous[$0] != current[$0] }
  }

  /// Deletes the single-file library that earlier versions wrote. Its profiles are not migrated.
  nonisolated func discardLegacyLibrary() {
    let url = directory.appendingPathComponent(Self.legacyLibraryFileName, isDirectory: false)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      try FileManager.default.removeItem(at: url)
      print("[Profiles] Deleted the earlier profile library \(url.path)")
    } catch {
      fputs("[Profiles] Cannot delete \(url.path): \(error.localizedDescription)\n", stderr)
    }
  }

  func checkpoint() throws -> RemappingProfileLibraryCheckpoint {
    let manager = FileManager.default
    var profileFiles: [String: RemappingProfileLibraryCheckpoint.File] = [:]
    for url in try profileFileURLs() {
      profileFiles[url.lastPathComponent] = try Self.persistedFile(at: url)
    }
    let checkpoint = RemappingProfileLibraryCheckpoint(
      cachedLibrary: library,
      cachedIssues: profileIssues,
      rootPermissions: try Self.permissions(
        at: directory,
        ifPresent: manager.fileExists(atPath: directory.path)
      ),
      profilesDirectoryPermissions: try Self.permissions(
        at: profilesDirectory,
        ifPresent: manager.fileExists(atPath: profilesDirectory.path)
      ),
      profileFiles: profileFiles,
      selections: manager.fileExists(atPath: selectionsURL.path)
        ? try Self.persistedFile(at: selectionsURL) : nil
    )
    _ = try loadIfNeeded()
    return checkpoint
  }

  func restore(_ checkpoint: RemappingProfileLibraryCheckpoint) throws {
    let manager = FileManager.default
    do {
      for url in try profileFileURLs() where checkpoint.profileFiles[url.lastPathComponent] == nil {
        try manager.removeItem(at: url)
      }
      if !checkpoint.profileFiles.isEmpty { try Self.createPrivateDirectory(profilesDirectory) }
      for (name, file) in checkpoint.profileFiles {
        try Self.restore(file, at: profilesDirectory.appendingPathComponent(name))
      }
      if let selections = checkpoint.selections {
        try Self.createPrivateDirectory(directory)
        try Self.restore(selections, at: selectionsURL)
      } else if manager.fileExists(atPath: selectionsURL.path) {
        try manager.removeItem(at: selectionsURL)
      }
      try Self.restoreDirectory(
        profilesDirectory,
        permissions: checkpoint.profilesDirectoryPermissions
      )
      try Self.restoreDirectory(directory, permissions: checkpoint.rootPermissions)
    } catch { throw RemappingProfileLibraryError.unwritableLibrary }
    library = checkpoint.cachedLibrary
    profileIssues = checkpoint.cachedIssues
  }

  private struct ResolvedSelection: Equatable {
    let applicationScope: RemappingApplicationScope?
    let profile: RemappingProfile?
  }

  private static func resolvedSelections(
    _ state: RemappingProfileLibraryState
  ) -> [RemappingProfileModel: [ResolvedSelection]] {
    let profilesByID = Dictionary(uniqueKeysWithValues: state.profiles.map { ($0.id, $0) })
    return Dictionary(grouping: state.activeProfiles, by: \.model).mapValues { entries in
      entries.map {
        ResolvedSelection(
          applicationScope: $0.applicationScope,
          profile: profilesByID[$0.profileID]
        )
      }
    }
  }

  private func requireCurrentData(_ expected: Data, at url: URL, issueID: UUID) throws {
    guard (try? Data(contentsOf: url)) == expected else {
      library = nil
      profileIssues = [:]
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
  }

  /// Writes `data` beside `url` under a name the loader does not read.
  private func backUp(_ data: Data, of url: URL) throws {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let backup = url.deletingLastPathComponent().appendingPathComponent(
      url.lastPathComponent + ".backup-" + formatter.string(from: Date()) + "-"
        + UUID().uuidString
    )
    do { try Self.writePrivate(data, to: backup) } catch {
      throw RemappingProfileLibraryError.unwritableLibrary
    }
  }

  private static func persistedFile(at url: URL) throws -> RemappingProfileLibraryCheckpoint.File {
    RemappingProfileLibraryCheckpoint.File(
      data: try read(url),
      permissions: try permissions(at: url, ifPresent: true)
    )
  }

  private static func restore(_ file: RemappingProfileLibraryCheckpoint.File, at url: URL) throws {
    if (try? Data(contentsOf: url)) != file.data { try file.data.write(to: url, options: .atomic) }
    try FileManager.default.setAttributes(
      [.posixPermissions: file.permissions ?? 0o600],
      ofItemAtPath: url.path
    )
  }

  /// Restores a directory's permissions, or removes it when it did not exist and is empty.
  private static func restoreDirectory(_ url: URL, permissions: Int?) throws {
    let manager = FileManager.default
    guard manager.fileExists(atPath: url.path) else { return }
    if let permissions {
      try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    } else if try manager.contentsOfDirectory(atPath: url.path).isEmpty {
      try manager.removeItem(at: url)
    }
  }
}
