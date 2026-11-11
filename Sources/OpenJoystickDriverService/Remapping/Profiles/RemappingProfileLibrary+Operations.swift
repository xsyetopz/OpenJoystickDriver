import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {
  /// Returns every profile, local and from packages, sorted by name.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when the library cannot be loaded.
  func profiles() throws -> [RemappingProfile] {
    try allProfiles(loadIfNeeded()).sorted(by: Self.profileOrder)
  }

  /// Returns the profiles, the active selections and the issues of the library.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when the library cannot be loaded.
  func snapshot() throws -> RemappingProfileLibrarySnapshot {
    let loaded = try loadIfNeeded()
    return RemappingProfileLibrarySnapshot(
      profiles: allProfiles(loaded).sorted(by: Self.profileOrder),
      activeProfiles: loaded.activeProfiles.map {
        RemappingActiveProfileSelection(
          model: $0.model,
          profileID: $0.profileID,
          applicationScope: $0.applicationScope
        )
      }.sorted(by: Self.activeProfileOrder),
      issues: profileIssues.keys.sorted { $0.uuidString < $1.uuidString }.map { issueID in
        let kind: ApplicationServiceRemappingProfileIssue.Kind
        let code: ErrorCode
        var staleFile: String?
        switch profileIssues[issueID] {
        case .damagedProfile(let fileName, _, let damageCode):
          kind = .damagedProfile
          code = damageCode
          if fileName.hasSuffix(".json") { staleFile = fileName }
        case .unusableLibrary, nil:
          kind = .unusableLibrary
          code = .corruptLibrary
        }
        return ApplicationServiceRemappingProfileIssue(
          id: issueID,
          kind: kind,
          code: code,
          message: staleFile.map {
            "\($0) was saved by an earlier version. Migrate it, or remove it."
          }
            ?? (kind == .damagedProfile
              ? "This saved profile could not be read and can be removed."
              : "The list of active profiles could not be read and must be reset."),
          fileName: staleFile
        )
      }
    )
  }

  /// Returns the profile `id`, or nil when none has it.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when the library cannot be loaded or is unusable.
  func profile(id: UUID) throws -> RemappingProfile? {
    let loaded = try loadIfNeeded()
    try requireUsableLibrary()
    return allProfiles(loaded).first { $0.id == id }
  }

  /// Adds `profile` to the library.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when the profile exists, is a package profile, is
  ///   invalid or has a name in use, or when the library needs recovery or cannot be written.
  @discardableResult
  func create(_ profile: RemappingProfile) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireNotPackageProfile(id: profile.id, in: proposed)
    try requireRecoveredLibrary()
    guard !proposed.profiles.contains(where: { $0.id == profile.id }) else {
      throw RemappingProfileLibraryError.profileAlreadyExists(profile.id)
    }
    try requireNameAvailable(profile, among: proposed.profiles, in: proposed)
    proposed.profiles.append(profile)
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [])
  }

  /// Checks that the library still holds `expectedCurrent` as the profile `profileID`.
  ///
  /// - Throws: ``RemappingProfileLibraryError/profileUpdateConflict(_:)`` when it differs,
  ///   ``RemappingProfileLibraryError/profileNotFound(_:)`` when it is missing and
  ///   ``RemappingProfileLibraryError/packageProfileReadOnly`` for a package profile.
  func requireCurrent(_ expectedCurrent: RemappingProfile, profileID: UUID) throws {
    guard expectedCurrent.id == profileID else {
      throw RemappingProfileLibraryError.profileUpdateConflict(profileID)
    }
    let loaded = try loadIfNeeded()
    try requireNotPackageProfile(id: profileID, in: loaded)
    guard let current = loaded.profiles.first(where: { $0.id == profileID }) else {
      throw RemappingProfileLibraryError.profileNotFound(profileID)
    }
    guard current == expectedCurrent else {
      throw RemappingProfileLibraryError.profileUpdateConflict(profileID)
    }
  }

  /// Replaces the profile `profile.id` when the library still holds `expectedCurrent`.
  ///
  /// A profile that changes its model or becomes a Joy-Con pair profile is deactivated.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when the profile is missing, changed, a package
  ///   profile, invalid or has a name in use, or when the library needs recovery or cannot be
  ///   written.
  @discardableResult
  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireNotPackageProfile(id: profile.id, in: proposed)
    try requireRecoveredLibrary()
    guard let index = proposed.profiles.firstIndex(where: { $0.id == profile.id }) else {
      throw RemappingProfileLibraryError.profileNotFound(profile.id)
    }
    guard expectedCurrent.id == profile.id, proposed.profiles[index] == expectedCurrent else {
      throw RemappingProfileLibraryError.profileUpdateConflict(profile.id)
    }
    var peers = proposed.profiles
    peers.remove(at: index)
    try requireNameAvailable(profile, among: peers, in: proposed)
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
    try requireNotPackageProfile(id: profile.id, in: proposed)
    try requireRecoveredLibrary()
    var modelsNeedingRefresh: Set<RemappingProfileModel> = []
    if let index = proposed.profiles.firstIndex(where: { $0.id == profile.id }) {
      var peers = proposed.profiles
      peers.remove(at: index)
      try requireNameAvailable(profile, among: peers, in: proposed)
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
      try requireNameAvailable(profile, among: proposed.profiles, in: proposed)
      proposed.profiles.append(profile)
    }
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: modelsNeedingRefresh)
  }

  /// Removes the profile `id` and its active selections.
  ///
  /// - Throws: ``RemappingProfileLibraryError/profileNotFound(_:)`` when no local profile has the
  ///   ID, and the other failures of a library change.
  @discardableResult
  func delete(id: UUID) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireNotPackageProfile(id: id, in: proposed)
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

  /// Activates the profile; one that produces no output needs `allowEmpty`.
  @discardableResult
  func activate(profileID: UUID, allowEmpty: Bool = false) throws -> RemappingProfileMutationImpact
  {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    let known = allProfiles(proposed)
    guard let profile = known.first(where: { $0.id == profileID }) else {
      throw RemappingProfileLibraryError.profileNotFound(profileID)
    }
    guard profile.joyConPair == nil else {
      throw RemappingProfileLibraryError.pairProfileRequiresExplicitSession
    }
    guard allowEmpty || !profile.producesNoOutput else {
      throw RemappingProfileLibraryError.profileProducesNoOutput(profileID)
    }
    do {
      try profile.validateProfileSwitches(among: known)
      try profile.validateSpeechVoices(using: speechOutput)
    } catch let error as RemappingValidationError {
      throw RemappingProfileLibraryError.invalidProfile(error)
    }
    let model = RemappingProfileModel(profile.device)
    let units = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0.device.unit) })
    // Replace any active entry for this profile or for the same model, unit, and application
    // scope. Multiple profiles per device are allowed — one per unit and application scope.
    proposed.activeProfiles.removeAll {
      $0.profileID == profileID
        || ($0.model == model && ($0.applicationScope ?? .global) == profile.applicationScope
          && units[$0.profileID, default: nil] == profile.device.unit)
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

  /// Removes the active selection of the profile `profileID`.
  ///
  /// - Throws: ``RemappingProfileLibraryError/profileNotFound(_:)`` when the profile is not active,
  ///   and the other failures of a library change.
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

  /// Removes every active selection of the model `vendorID` and `productID`.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when the library needs recovery or cannot be
  ///   written.
  @discardableResult
  func deactivateAll(vendorID: UInt16, productID: UInt16) throws -> RemappingProfileMutationImpact {
    var proposed = try loadIfNeeded()
    try requireRecoveredLibrary()
    let model = RemappingProfileModel(vendorID: vendorID, productID: productID)
    proposed.activeProfiles.removeAll { $0.model == model }
    try replace(with: proposed)
    return RemappingProfileMutationImpact(modelsNeedingRefresh: [model])
  }

  /// Returns the active profile for the unit `unit` of the model, whatever the frontmost
  /// application.
  ///
  /// - Throws: ``RemappingProfileLibraryError`` when the library cannot be loaded or is unusable.
  func activeProfile(
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) throws -> RemappingProfile? {
    try activeProfile(
      vendorID: vendorID,
      productID: productID,
      unit: unit,
      frontmostAppID: nil
    )
  }

  /// The profile that drives one controller.
  ///
  /// Profiles for another unit of the model never apply; within each tier below, a profile for
  /// `unit` wins over one for every unit.
  func activeProfile(
    vendorID: UInt16,
    productID: UInt16,
    unit: String?,
    frontmostAppID: String?
  ) throws -> RemappingProfile? {
    let loaded = try loadIfNeeded()
    try requireUsableLibrary()
    let model = RemappingProfileModel(vendorID: vendorID, productID: productID)
    let profilesByID = Dictionary(uniqueKeysWithValues: allProfiles(loaded).map { ($0.id, $0) })
    let candidates = loaded.activeProfiles.compactMap {
      entry -> (scope: RemappingApplicationScope?, profile: RemappingProfile)? in
      guard entry.model == model, let profile = profilesByID[entry.profileID] else { return nil }
      guard profile.device.unit == nil || profile.device.unit == unit else { return nil }
      return (entry.applicationScope, profile)
    }
    func preferred(
      _ matches: [(scope: RemappingApplicationScope?, profile: RemappingProfile)]
    ) -> RemappingProfile? {
      (matches.last { $0.profile.device.unit != nil } ?? matches.last)?.profile
    }

    // Prefer an app-scoped profile matching the frontmost app (last activated wins)
    if let appID = frontmostAppID,
      let profile = preferred(
        candidates.filter { $0.scope == .application(appID: appID) }
      )
    {
      return profile
    }

    // Fall back to the last-activated global-scope profile
    if let profile = preferred(candidates.filter { $0.scope == .global }) { return profile }

    // Fall back to the last active profile for this controller
    return preferred(candidates)
  }
}
