import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {

  func loadIfNeeded() throws -> RemappingProfileLibraryState {
    if let library { return library }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      let empty = RemappingProfileLibraryState()
      library = empty
      return empty
    }

    let data: Data
    do { data = try Data(contentsOf: fileURL) } catch {
      throw RemappingProfileLibraryError.unreadableLibrary
    }
    guard data.count <= Self.maximumEncodedBytes else { return loadUnusableLibrary(data) }

    let decoded: RemappingProfileLibraryState
    do { decoded = try JSONDecoder().decode(RemappingProfileLibraryState.self, from: data) } catch {
      do {
        let recovered = try recoverProfiles(from: data)
        library = recovered
        originalRecoveryData = data
        return recovered
      } catch { return loadUnusableLibrary(data) }
    }
    do {
      var normalized = decoded
      normalized.activeProfiles = Self.normalizedActiveProfiles(decoded.activeProfiles)
      try validate(normalized)
      library = normalized
      return normalized
    } catch {
      do {
        let recovered = try recoverProfiles(from: data)
        library = recovered
        originalRecoveryData = data
        return recovered
      } catch { return loadUnusableLibrary(data) }
    }
  }

  func replace(with proposed: RemappingProfileLibraryState) throws {
    try validate(proposed)
    let data: Data
    do { data = try JSONEncoder().encode(proposed) } catch {
      throw RemappingProfileLibraryError.unwritableLibrary
    }
    guard data.count <= Self.maximumEncodedBytes else {
      throw RemappingProfileLibraryError.librarySizeExceeded(data.count)
    }

    let manager = FileManager.default
    let directory = fileURL.deletingLastPathComponent()
    do {
      try manager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try data.write(to: fileURL, options: .atomic)
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    } catch { throw RemappingProfileLibraryError.unwritableLibrary }
    library = proposed
    profileIssues = [:]
    originalRecoveryData = nil
  }

  func requireRecoveredLibrary() throws {
    guard profileIssues.isEmpty else { throw RemappingProfileLibraryError.profileRecoveryRequired }
  }

  func requireUsableLibrary() throws {
    guard
      !profileIssues.values.contains(where: {
        if case .unusableLibrary = $0 { return true }
        return false
      })
    else { throw RemappingProfileLibraryError.corruptLibrary }
  }

  func recoverProfiles(
    from data: Data,
    requireDamagedProfile: Bool = true
  ) throws -> RemappingProfileLibraryState {
    let root = try Self.libraryRoot(from: data)
    let objects = try Self.profileObjects(from: root)
    var profiles: [RemappingProfile] = []
    var issues: [UUID: RecoveryIssue] = [:]
    for (index, object) in objects.enumerated() {
      do {
        let profileData = try JSONSerialization.data(withJSONObject: object)
        let profile = try JSONDecoder().decode(RemappingProfile.self, from: profileData)
        try validate(profile, in: profiles)
        profiles.append(profile)
      } catch { issues[UUID()] = .damagedProfile(index: index) }
    }
    if requireDamagedProfile, issues.isEmpty { throw RemappingProfileLibraryError.corruptLibrary }
    let retainedIDs = Set(profiles.map(\.id))
    let activeProfiles: [RemappingPersistedActiveProfile] = (root["activeProfiles"] as? [Any] ?? [])
      .compactMap { object in
        guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object),
          let active = try? JSONDecoder().decode(RemappingPersistedActiveProfile.self, from: data),
          retainedIDs.contains(active.profileID)
        else { return nil }
        return active
      }
    profileIssues = issues
    return RemappingProfileLibraryState(
      profiles: profiles,
      activeProfiles: Self.normalizedActiveProfiles(activeProfiles)
    )
  }

  private func loadUnusableLibrary(_ data: Data) -> RemappingProfileLibraryState {
    let empty = RemappingProfileLibraryState()
    profileIssues = [UUID(): .unusableLibrary]
    originalRecoveryData = data
    library = empty
    return empty
  }

  func backUp(_ data: Data) throws {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let backup = fileURL.deletingLastPathComponent().appendingPathComponent(
      fileURL.lastPathComponent + ".backup-" + formatter.string(from: Date()) + "-"
        + UUID().uuidString
    )
    do { try data.write(to: backup, options: .atomic) } catch {
      throw RemappingProfileLibraryError.unwritableLibrary
    }
  }

  func requireCurrentRecoveryData(_ expected: Data, issueID: UUID) throws {
    let current: Data
    do { current = try Data(contentsOf: fileURL) } catch {
      throw RemappingProfileLibraryError.unreadableLibrary
    }
    guard current == expected else {
      library = nil
      profileIssues = [:]
      originalRecoveryData = nil
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
  }

  func replaceRawLibrary(_ data: Data, clearRecovery: Bool) throws {
    let directory = fileURL.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path
      )
      try data.write(to: fileURL, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    } catch { throw RemappingProfileLibraryError.unwritableLibrary }
    library = nil
    if clearRecovery {
      profileIssues = [:]
      originalRecoveryData = nil
    }
  }

  static func libraryRoot(from data: Data) throws -> [String: Any] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(root.keys).isSubset(of: ["profiles", "activeProfiles"]), root["profiles"] != nil
    else { throw RemappingProfileLibraryError.corruptLibrary }
    return root
  }

  static func profileObjects(from root: [String: Any]) throws -> [Any] {
    guard let profiles = root["profiles"] as? [Any] else {
      throw RemappingProfileLibraryError.corruptLibrary
    }
    return profiles
  }

  func validate(_ profile: RemappingProfile, in peers: [RemappingProfile]) throws {
    do { try profile.validate() } catch let error as RemappingValidationError {
      throw RemappingProfileLibraryError.invalidProfile(error)
    } catch { throw RemappingProfileLibraryError.invalidProfile(.encodingFailed) }
    let normalizedName = Self.normalizedName(profile.name)
    guard !peers.contains(where: { Self.normalizedName($0.name) == normalizedName }) else {
      throw RemappingProfileLibraryError.duplicateName(profile.name)
    }
  }

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
    let profilesByID = Dictionary(uniqueKeysWithValues: library.profiles.map { ($0.id, $0) })
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

  static func normalizedName(_ name: String) -> String {
    name.lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  static func profileOrder(_ lhs: RemappingProfile, _ rhs: RemappingProfile) -> Bool {
    let leftName = normalizedName(lhs.name)
    let rightName = normalizedName(rhs.name)
    if leftName != rightName { return leftName < rightName }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  static func permissions(at url: URL, ifPresent: Bool) throws -> Int? {
    guard ifPresent else { return nil }
    do {
      return try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    } catch { throw RemappingProfileLibraryError.unreadableLibrary }
  }

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
