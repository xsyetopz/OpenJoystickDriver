import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {
  /// A file the library could not use, with the bytes it read so recovery acts on that content.
  enum RecoveryIssue: Equatable, Sendable {
    /// A profile file that could not be read, with its name, bytes and error code.
    case damagedProfile(fileName: String, data: Data, code: ErrorCode)
    /// The list of active profiles could not be read, with its bytes.
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
    guard case .damagedProfile(let fileName, let data, _) = profileIssues[issueID] else {
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

  /// Backs up unreadable selections and replaces them with none.
  ///
  /// The profiles are kept.
  @discardableResult
  func resetDamagedLibrary(issueID: UUID) throws -> RemappingProfileMutationImpact {
    _ = try loadIfNeeded()
    guard case .unusableLibrary(let data) = profileIssues[issueID] else {
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
    try requireCurrentData(data, at: selectionsURL, issueID: issueID)
    try backUp(data, of: selectionsURL)
    do {
      try Self.writePrivate(
        DocumentCoder.encode([RemappingPersistedActiveProfile]()),
        to: selectionsURL
      )
    } catch {
      throw RemappingProfileLibraryError.unwritableLibrary
    }
    profileIssues[issueID] = nil
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [])
  }

  /// Discards the cached library and reads the profile files and the installed packages again.
  ///
  /// Returns the models whose active profiles, resolved to their content, changed.
  func reload() throws -> Set<RemappingProfileModel> {
    let previous = library.map { resolvedSelections($0) } ?? [:]
    library = nil
    let current = resolvedSelections(try loadIfNeeded())
    return Set(previous.keys).union(current.keys).filter { previous[$0] != current[$0] }
  }

  /// Captures the files and permissions of the library.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when a file cannot be read.
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

  /// Writes the files and permissions of `checkpoint` back and restores the cached state.
  ///
  /// - Throws: ``RemappingProfileLibraryError/unwritableLibrary`` when a file cannot be restored.
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

  /// An active selection with its profile resolved.
  private struct ResolvedSelection: Equatable {
    /// The applications the selection applies to, or nil for every application.
    let applicationScope: RemappingApplicationScope?
    /// The profile, or nil when it is missing.
    let profile: RemappingProfile?
  }

  /// Returns the active selections of `state` with their profiles, by model.
  private func resolvedSelections(
    _ state: RemappingProfileLibraryState
  ) -> [RemappingProfileModel: [ResolvedSelection]] {
    let profilesByID = Dictionary(uniqueKeysWithValues: allProfiles(state).map { ($0.id, $0) })
    return Dictionary(grouping: state.activeProfiles, by: \.model).mapValues { entries in
      entries.map {
        ResolvedSelection(
          applicationScope: $0.applicationScope,
          profile: profilesByID[$0.profileID]
        )
      }
    }
  }

  /// Throws unless the file at `url` still holds `expected`.
  ///
  /// - Throws: ``RemappingProfileLibraryError/profileIssueNotFound(_:)`` for `issueID` when it
  ///   differs.
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

  /// Reads the data and permissions of the file at `url`.
  private static func persistedFile(at url: URL) throws -> RemappingProfileLibraryCheckpoint.File {
    RemappingProfileLibraryCheckpoint.File(
      data: try read(url),
      permissions: try permissions(at: url, ifPresent: true)
    )
  }

  /// Writes the data of `file` to `url` when it differs and sets the permissions of `file`.
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
