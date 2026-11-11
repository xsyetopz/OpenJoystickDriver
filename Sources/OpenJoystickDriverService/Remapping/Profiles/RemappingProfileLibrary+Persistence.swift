import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {

  /// Reads every profile file and the selections.
  ///
  /// A profile file that cannot be used becomes a damaged-profile issue, and selections that cannot
  /// be read become an unusable-library issue.
  func loadIfNeeded() throws -> RemappingProfileLibraryState {
    if let library { return library }
    var issues: [RecoveryIssue] = []
    let packaged = loadPackageProfiles()
    var profiles: [RemappingProfile] = []
    for url in try profileFileURLs() {
      let data = try Self.read(url)
      do {
        let profile = try RemappingProfileFileStore.load(from: data, file: url.path)
        guard url.lastPathComponent == Self.profileFileName(profile.id) else {
          throw RemappingProfileLibraryError.corruptLibrary
        }
        try validate(profile, in: profiles)
        profiles.append(profile)
      } catch {
        issues.append(
          .damagedProfile(
            fileName: url.lastPathComponent,
            data: data,
            code: Self.damageCode(error)
          )
        )
      }
    }

    var activeProfiles: [RemappingPersistedActiveProfile] = []
    if FileManager.default.fileExists(atPath: selectionsURL.path) {
      let data = try Self.read(selectionsURL)
      if data.count <= Self.maximumEncodedBytes,
        let decoded = try? DocumentCoder.decode(
          [RemappingPersistedActiveProfile].self,
          from: data,
          file: selectionsURL.path
        )
      {
        let profilesByID = Dictionary(
          uniqueKeysWithValues: allProfiles(
            RemappingProfileLibraryState(profiles: profiles),
            packageProfiles: packaged
          ).map { ($0.id, $0) }
        )
        activeProfiles = Self.normalizedActiveProfiles(
          decoded.filter { active in
            guard let profile = profilesByID[active.profileID] else { return false }
            return active.model == RemappingProfileModel(profile.device)
              && profile.joyConPair == nil
          }
        )
      } else {
        issues.append(.unusableLibrary(data: data))
      }
    }

    let loaded = RemappingProfileLibraryState(profiles: profiles, activeProfiles: activeProfiles)
    setIssues(issues)
    packageProfiles = packaged
    library = loaded
    return loaded
  }

  /// The error code of a profile file that cannot be used: the code a request gives the same
  /// failure for a library error, otherwise the code of the refused document.
  static func damageCode(_ error: any Error) -> ErrorCode {
    guard let error = error as? RemappingProfileLibraryError else {
      return RemappingProfileFileStore.problemCode(error)
    }
    return RemappingRequestCoordinator.rpcError(error).code.errorCode
  }

  /// Writes the profile files that changed, the selections when they changed, and deletes the
  /// files of removed profiles.
  func replace(with proposed: RemappingProfileLibraryState) throws {
    try validate(proposed)
    let current = try loadIfNeeded()
    let manager = FileManager.default
    do {
      try Self.createPrivateDirectory(profilesDirectory)
      try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      for profile in proposed.profiles where !current.profiles.contains(profile) {
        let data = Data(try RemappingProfileFileStore.encodedPlist(profile).utf8)
        try Self.writePrivate(data, to: profileURL(profile.id))
      }
      if proposed.activeProfiles != current.activeProfiles {
        try Self.writePrivate(DocumentCoder.encode(proposed.activeProfiles), to: selectionsURL)
      }
      let keptIDs = Set(proposed.profiles.map(\.id))
      for profile in current.profiles where !keptIDs.contains(profile.id) {
        let url = profileURL(profile.id)
        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
      }
    } catch { throw RemappingProfileLibraryError.unwritableLibrary }
    library = proposed
  }

  /// The `*.plist` files in `Profiles/`, sorted by name.
  func profileFileURLs() throws -> [URL] {
    guard FileManager.default.fileExists(atPath: profilesDirectory.path) else { return [] }
    do {
      return try FileManager.default.contentsOfDirectory(
        at: profilesDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      .filter { $0.pathExtension == "plist" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    } catch { throw RemappingProfileLibraryError.unreadableLibrary }
  }

  /// Throws unless every issue of the library is fixed.
  ///
  /// - Throws: ``RemappingProfileLibraryError/profileRecoveryRequired``.
  func requireRecoveredLibrary() throws {
    guard profileIssues.isEmpty else { throw RemappingProfileLibraryError.profileRecoveryRequired }
  }

  /// Throws when the list of active profiles is unusable.
  ///
  /// - Throws: ``RemappingProfileLibraryError/corruptLibrary``.
  func requireUsableLibrary() throws {
    guard
      !profileIssues.values.contains(where: {
        if case .unusableLibrary = $0 { return true }
        return false
      })
    else { throw RemappingProfileLibraryError.corruptLibrary }
  }

  /// Reads the file at `url`.
  ///
  /// - Throws: ``RemappingProfileLibraryError/unreadableLibrary``.
  static func read(_ url: URL) throws -> Data {
    do { return try Data(contentsOf: url) } catch {
      throw RemappingProfileLibraryError.unreadableLibrary
    }
  }

  /// Creates the directory `url` with owner-only permissions.
  static func createPrivateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
  }

  /// Writes `data` atomically to `url` with owner-only permissions.
  static func writePrivate(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  /// Throws unless `profile` is valid and no profile of `peers` has its name.
  ///
  /// - Throws: ``RemappingProfileLibraryError/invalidProfile(_:)`` or
  ///   ``RemappingProfileLibraryError/duplicateName(_:)``.
  func validate(_ profile: RemappingProfile, in peers: [RemappingProfile]) throws {
    do { try profile.validate() } catch let error as RemappingValidationError {
      throw RemappingProfileLibraryError.invalidProfile(error)
    } catch { throw RemappingProfileLibraryError.invalidProfile(.encodingFailed) }
    let normalizedName = Self.normalizedName(profile.name)
    guard !peers.contains(where: { Self.normalizedName($0.name) == normalizedName }) else {
      throw RemappingProfileLibraryError.duplicateName(profile.name)
    }
  }

  /// Throws unless the profiles of `library` and its active selections are consistent.
  ///
  /// - Throws: ``RemappingProfileLibraryError/profileCountExceeded(_:)`` or
  ///   ``RemappingProfileLibraryError/corruptLibrary``, and the failures of the profile check.
  func validate(_ library: RemappingProfileLibraryState) throws {
    guard library.profiles.count <= Self.maximumProfileCount else {
      throw RemappingProfileLibraryError.profileCountExceeded(library.profiles.count)
    }
    var profileIDs: Set<UUID> = []
    for profile in library.profiles {
      guard profileIDs.insert(profile.id).inserted else {
        throw RemappingProfileLibraryError.corruptLibrary
      }
      try validate(profile, in: library.profiles.filter { $0.id != profile.id })
    }
    let profilesByID = Dictionary(uniqueKeysWithValues: allProfiles(library).map { ($0.id, $0) })
    // Each active profile entry must reference a real profile with a matching device model.
    // Multiple active profiles per model are allowed (per-app auto-switch).
    var seenActiveKeys: Set<String> = []
    for active in library.activeProfiles {
      guard let profile = profilesByID[active.profileID] else {
        throw RemappingProfileLibraryError.corruptLibrary
      }
      guard active.model == RemappingProfileModel(profile.device) else {
        throw RemappingProfileLibraryError.corruptLibrary
      }
      guard profile.joyConPair == nil else { throw RemappingProfileLibraryError.corruptLibrary }
      // No duplicate (model, profileID, scope) entries
      let scopeKey = String(describing: active.applicationScope)
      let key = "\(active.model.vendorID):\(active.model.productID):\(active.profileID):\(scopeKey)"
      guard seenActiveKeys.insert(key).inserted else {
        throw RemappingProfileLibraryError.corruptLibrary
      }
    }
  }

  /// Keeps only the last entry per model and application scope, matching what routing uses.
  static func normalizedActiveProfiles(
    _ entries: [RemappingPersistedActiveProfile]
  ) -> [RemappingPersistedActiveProfile] {
    var seen: Set<String> = []
    var kept: [RemappingPersistedActiveProfile] = []
    for entry in entries.reversed() {
      let scope = String(describing: entry.applicationScope ?? .global)
      let key = "\(entry.model.vendorID):\(entry.model.productID):\(scope)"
      if seen.insert(key).inserted { kept.append(entry) }
    }
    return kept.reversed()
  }

  /// Returns `name` in the form that the name check compares.
  static func normalizedName(_ name: String) -> String {
    RemappingProfile.normalizedName(name)
  }

  /// Orders profiles by normalized name, then by ID.
  static func profileOrder(_ lhs: RemappingProfile, _ rhs: RemappingProfile) -> Bool {
    let leftName = normalizedName(lhs.name)
    let rightName = normalizedName(rhs.name)
    if leftName != rightName { return leftName < rightName }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  /// Returns the POSIX permissions of `url`, or nil when `ifPresent` is false.
  ///
  /// - Throws: ``RemappingProfileLibraryError/unreadableLibrary`` when the attributes cannot be
  ///   read.
  static func permissions(at url: URL, ifPresent: Bool) throws -> Int? {
    guard ifPresent else { return nil }
    do {
      return try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    } catch { throw RemappingProfileLibraryError.unreadableLibrary }
  }

  /// Orders active selections by vendor ID, product ID, then profile ID.
  static func activeProfileOrder(
    _ lhs: RemappingActiveProfileSelection,
    _ rhs: RemappingActiveProfileSelection
  ) -> Bool {
    if lhs.model.vendorID != rhs.model.vendorID { return lhs.model.vendorID < rhs.model.vendorID }
    if lhs.model.productID != rhs.model.productID {
      return lhs.model.productID < rhs.model.productID
    }
    return lhs.profileID.uuidString < rhs.profileID.uuidString
  }
}
