import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {
  enum RecoveryIssue {
    case damagedProfile(index: Int)
    case unusableLibrary
  }

  static var defaultFileURL: URL {
    let manager = FileManager.default
    let directory =
      manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return directory.appendingPathComponent("OpenJoystickDriver", isDirectory: true)
      .appendingPathComponent("RemappingProfiles.json", isDirectory: false)
  }

  func profiles() throws -> [RemappingProfile] {
    try loadIfNeeded().profiles.sorted(by: Self.profileOrder)
  }

  func snapshot() throws -> RemappingProfileLibrarySnapshot {
    let loaded = try loadIfNeeded()
    return RemappingProfileLibrarySnapshot(
      profiles: loaded.profiles.sorted(by: Self.profileOrder),
      activeProfiles: loaded.activeProfiles.map {
        RemappingActiveProfileSelection(
          model: $0.model,
          profileID: $0.profileID,
          applicationScope: $0.applicationScope
        )
      }.sorted(by: Self.activeProfileOrder),
      issues: profileIssues.keys.sorted { $0.uuidString < $1.uuidString }.map { issueID in
        let kind: ApplicationServiceRemappingProfileIssue.Kind =
          switch profileIssues[issueID] {
          case .damagedProfile: .damagedProfile
          case .unusableLibrary, nil: .unusableLibrary
          }
        return ApplicationServiceRemappingProfileIssue(
          id: issueID,
          kind: kind,
          message: kind == .damagedProfile
            ? "This saved profile could not be read and can be removed."
            : "The saved profile library could not be read and must be reset."
        )
      }
    )
  }

  func profile(id: UUID) throws -> RemappingProfile? {
    let loaded = try loadIfNeeded()
    try requireUsableLibrary()
    return loaded.profiles.first { $0.id == id }
  }

  @discardableResult
  func deleteDamagedProfile(issueID: UUID) throws -> RemappingProfileMutationImpact {
    _ = try loadIfNeeded()
    guard case .damagedProfile(let index) = profileIssues[issueID], let originalRecoveryData else {
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
    try requireCurrentRecoveryData(originalRecoveryData, issueID: issueID)
    var root = try Self.libraryRoot(from: originalRecoveryData)
    var profiles = try Self.profileObjects(from: root)
    guard profiles.indices.contains(index) else {
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
    profiles.remove(at: index)
    root["profiles"] = profiles
    let recovered = try recoverProfiles(
      from: try JSONSerialization.data(withJSONObject: root),
      requireDamagedProfile: false
    )
    root["activeProfiles"] = try recovered.activeProfiles.map {
      try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
    }
    try backUp(originalRecoveryData)
    try replaceRawLibrary(try JSONSerialization.data(withJSONObject: root), clearRecovery: true)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [])
  }

  @discardableResult
  func resetDamagedLibrary(issueID: UUID) throws -> RemappingProfileMutationImpact {
    _ = try loadIfNeeded()
    guard case .unusableLibrary = profileIssues[issueID], let originalRecoveryData else {
      throw RemappingProfileLibraryError.profileIssueNotFound(issueID)
    }
    try requireCurrentRecoveryData(originalRecoveryData, issueID: issueID)
    try backUp(originalRecoveryData)
    try replace(with: RemappingProfileLibraryState())
    profileIssues = [:]
    self.originalRecoveryData = nil
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [])
  }

  func checkpoint() throws -> RemappingProfileLibraryCheckpoint {
    let manager = FileManager.default
    let parentURL = fileURL.deletingLastPathComponent()
    let parentExisted = manager.fileExists(atPath: parentURL.path)
    let parentPermissions = try Self.permissions(at: parentURL, ifPresent: parentExisted)
    let fileExisted = manager.fileExists(atPath: fileURL.path)
    let filePermissions = try Self.permissions(at: fileURL, ifPresent: fileExisted)
    let persistedData: Data?
    if fileExisted {
      do { persistedData = try Data(contentsOf: fileURL) } catch {
        throw RemappingProfileLibraryError.unreadableLibrary
      }
    } else {
      persistedData = nil
    }
    let cachedLibrary = library
    _ = try loadIfNeeded()
    return RemappingProfileLibraryCheckpoint(
      cachedLibrary: cachedLibrary,
      persistedData: persistedData,
      parentExisted: parentExisted,
      parentPermissions: parentPermissions,
      filePermissions: filePermissions
    )
  }

  func restore(_ checkpoint: RemappingProfileLibraryCheckpoint) throws {
    let manager = FileManager.default
    let directory = fileURL.deletingLastPathComponent()
    do {
      if let data = checkpoint.persistedData {
        try manager.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: fileURL, options: .atomic)
        try manager.setAttributes(
          [.posixPermissions: checkpoint.parentPermissions ?? 0o700],
          ofItemAtPath: directory.path
        )
        try manager.setAttributes(
          [.posixPermissions: checkpoint.filePermissions ?? 0o600],
          ofItemAtPath: fileURL.path
        )
      } else {
        if manager.fileExists(atPath: fileURL.path) { try manager.removeItem(at: fileURL) }
        if !checkpoint.parentExisted, manager.fileExists(atPath: directory.path),
          try manager.contentsOfDirectory(atPath: directory.path).isEmpty
        {
          try manager.removeItem(at: directory)
        } else if let permissions = checkpoint.parentPermissions {
          try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
        }
      }
    } catch { throw RemappingProfileLibraryError.unwritableLibrary }
    library = checkpoint.cachedLibrary
  }

  @discardableResult
  func create(_ profile: RemappingProfile) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    guard !proposed.profiles.contains(where: { $0.id == profile.id }) else {
      throw RemappingProfileLibraryError.profileAlreadyExists(profile.id)
    }
    try validate(profile, in: proposed.profiles)
    proposed.profiles.append(profile)
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [])
  }

  func requireCurrent(_ expectedCurrent: RemappingProfile, profileID: UUID) throws {
    guard expectedCurrent.id == profileID else {
      throw RemappingProfileLibraryError.profileUpdateConflict(profileID)
    }
    let loaded = try loadIfNeeded()
    guard let current = loaded.profiles.first(where: { $0.id == profileID }) else {
      throw RemappingProfileLibraryError.profileNotFound(profileID)
    }
    guard current == expectedCurrent else {
      throw RemappingProfileLibraryError.profileUpdateConflict(profileID)
    }
  }

  @discardableResult
  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    guard let index = proposed.profiles.firstIndex(where: { $0.id == profile.id }) else {
      throw RemappingProfileLibraryError.profileNotFound(profile.id)
    }
    guard expectedCurrent.id == profile.id, proposed.profiles[index] == expectedCurrent else {
      throw RemappingProfileLibraryError.profileUpdateConflict(profile.id)
    }
    var peers = proposed.profiles
    peers.remove(at: index)
    try validate(profile, in: peers)
    let previousModel = RemappingProfileModel(proposed.profiles[index].device)
    let wasActive = proposed.activeProfiles.contains { $0.profileID == profile.id }
    proposed.profiles[index] = profile
    let currentModel = RemappingProfileModel(profile.device)
    if previousModel != currentModel || profile.joyConPair != nil {
      proposed.activeProfiles.removeAll { $0.profileID == profile.id }
    }
    try replace(with: proposed)
    return RemappingProfileMutationImpact(
      modelsNeedingRefresh: wasActive ? [previousModel, currentModel] : []
    )
  }

  /// Imports a profile, replacing the existing profile with the same identifier.
  @discardableResult
  func importProfile(_ profile: RemappingProfile) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    var modelsNeedingRefresh: Set<RemappingProfileModel> = []
    if let index = proposed.profiles.firstIndex(where: { $0.id == profile.id }) {
      var peers = proposed.profiles
      peers.remove(at: index)
      try validate(profile, in: peers)
      let previousModel = RemappingProfileModel(proposed.profiles[index].device)
      let currentModel = RemappingProfileModel(profile.device)
      if proposed.activeProfiles.contains(where: { $0.profileID == profile.id }) {
        modelsNeedingRefresh.insert(previousModel)
        modelsNeedingRefresh.insert(currentModel)
      }
      proposed.profiles[index] = profile
      if previousModel != currentModel || profile.joyConPair != nil {
        proposed.activeProfiles.removeAll { $0.profileID == profile.id }
      }
    } else {
      try validate(profile, in: proposed.profiles)
      proposed.profiles.append(profile)
    }
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: modelsNeedingRefresh)
  }

  @discardableResult
  func delete(id: UUID) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    guard let index = proposed.profiles.firstIndex(where: { $0.id == id }) else {
      throw RemappingProfileLibraryError.profileNotFound(id)
    }
    let profile = proposed.profiles.remove(at: index)
    let wasActive = proposed.activeProfiles.contains { $0.profileID == id }
    proposed.activeProfiles.removeAll { $0.profileID == id }
    try replace(with: proposed)
    return RemappingProfileMutationImpact(
      modelsNeedingRefresh: wasActive ? [RemappingProfileModel(profile.device)] : []
    )
  }

  @discardableResult
  func activate(profileID: UUID) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    guard let profile = proposed.profiles.first(where: { $0.id == profileID }) else {
      throw RemappingProfileLibraryError.profileNotFound(profileID)
    }
    guard profile.joyConPair == nil else {
      throw RemappingProfileLibraryError.pairProfileRequiresExplicitSession
    }
    let model = RemappingProfileModel(profile.device)
    // Replace any active entry for this profile or for the same model and application scope.
    // Multiple profiles per device are allowed — one per application scope.
    proposed.activeProfiles.removeAll {
      $0.profileID == profileID
        || ($0.model == model && ($0.applicationScope ?? .global) == profile.applicationScope)
    }
    proposed.activeProfiles.append(
      RemappingPersistedActiveProfile(
        model: model,
        profileID: profile.id,
        applicationScope: profile.applicationScope
      )
    )
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [model])
  }

  @discardableResult
  func deactivate(profileID: UUID) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    guard let existing = proposed.activeProfiles.first(where: { $0.profileID == profileID }) else {
      throw RemappingProfileLibraryError.profileNotFound(profileID)
    }
    proposed.activeProfiles.removeAll { $0.profileID == profileID }
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [existing.model])
  }

  @discardableResult
  func deactivateAll(vendorID: UInt16, productID: UInt16) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    let model = RemappingProfileModel(vendorID: vendorID, productID: productID)
    proposed.activeProfiles.removeAll { $0.model == model }
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [model])
  }

  func activeProfile(vendorID: UInt16, productID: UInt16) throws -> RemappingProfile? {
    try activeProfile(vendorID: vendorID, productID: productID, frontmostBundleIdentifier: nil)
  }

  func activeProfile(
    vendorID: UInt16,
    productID: UInt16,
    frontmostBundleIdentifier: String?
  ) throws -> RemappingProfile? {
    let loaded = try loadIfNeeded()
    try requireUsableLibrary()
    let model = RemappingProfileModel(vendorID: vendorID, productID: productID)
    let candidates = loaded.activeProfiles.filter { $0.model == model }
    guard !candidates.isEmpty else { return nil }
    let profilesByID = Dictionary(uniqueKeysWithValues: loaded.profiles.map { ($0.id, $0) })

    // Prefer an app-scoped profile matching the frontmost app (last activated wins)
    if let bundleID = frontmostBundleIdentifier {
      if let appMatch = candidates.last(where: { entry in
        guard case .application(let scope) = entry.applicationScope else { return false }
        return scope == bundleID
      }), let profile = profilesByID[appMatch.profileID] {
        return profile
      }
    }

    // Fall back to the last-activated global-scope profile
    if let globalMatch = candidates.last(where: { entry in entry.applicationScope == .global }),
      let profile = profilesByID[globalMatch.profileID]
    {
      return profile
    }

    // Fall back to the last active profile for this model
    if let last = candidates.last, let profile = profilesByID[last.profileID] { return profile }

    return nil
  }
}
