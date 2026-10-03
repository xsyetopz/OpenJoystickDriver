import Foundation
import OpenJoystickDriverKit

/// Stable failures from the locally persisted remapping-profile library.
enum RemappingProfileLibraryError: Error, Equatable, LocalizedError, Sendable {
  case corruptLibrary
  case duplicateName(String)
  case invalidProfile(RemappingValidationError)
  case profileCountExceeded(Int)
  case profileAlreadyExists(UUID)
  case profileNotFound(UUID)
  case pairProfileRequiresExplicitSession
  case profileUpdateConflict(UUID)
  case unreadableLibrary
  case unwritableLibrary
  case profileRecoveryRequired
  case profileIssueNotFound(UUID)

  var errorDescription: String? {
    switch self {
    case .corruptLibrary: "The active remapping profile list is damaged."
    case .duplicateName(let name): "A remapping profile named \(name) already exists."
    case .invalidProfile(let error): error.localizedDescription
    case .profileCountExceeded(let count): "There cannot be \(count) remapping profiles."
    case .profileAlreadyExists(let id): "The remapping profile \(id.uuidString) already exists."
    case .profileNotFound(let id): "The remapping profile \(id.uuidString) does not exist."
    case .pairProfileRequiresExplicitSession:
      "Paired Joy-Con profiles are started with an explicit pair session."
    case .profileUpdateConflict(let id):
      "The remapping profile \(id.uuidString) changed since it was read."
    case .unreadableLibrary: "A remapping profile file could not be read."
    case .unwritableLibrary: "A remapping profile file could not be written."
    case .profileRecoveryRequired:
      "Repair or remove the damaged profile files before changing profiles."
    case .profileIssueNotFound: "The selected damaged profile is no longer current."
    }
  }
}

/// The single application-service writer for locally authored remapping profiles.
///
/// Each profile is its own `Profiles/<id>.json` file in the profile-file format, and the active
/// selections are `ActiveProfiles.json`, both under `directory`.
actor RemappingProfileLibrary {
  static let maximumProfileCount = RemappingPayloadLimits.maximumProfileCount
  static let maximumEncodedBytes = RemappingPayloadLimits.maximumEncodedBytes
  static let selectionsFileName = "ActiveProfiles.json"
  static let legacyLibraryFileName = "RemappingProfiles.json"

  let directory: URL
  var library: RemappingProfileLibraryState?
  var profileIssues: [UUID: RecoveryIssue] = [:]

  init(directory: URL = RemappingProfileLibrary.defaultDirectory) { self.directory = directory }

  static var defaultDirectory: URL {
    let manager = FileManager.default
    let directory =
      manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return directory.appendingPathComponent("OpenJoystickDriver", isDirectory: true)
  }

  nonisolated var profilesDirectory: URL {
    directory.appendingPathComponent("Profiles", isDirectory: true)
  }

  nonisolated var selectionsURL: URL {
    directory.appendingPathComponent(Self.selectionsFileName, isDirectory: false)
  }

  nonisolated func profileURL(_ id: UUID) -> URL {
    profilesDirectory.appendingPathComponent(Self.profileFileName(id), isDirectory: false)
  }

  static func profileFileName(_ id: UUID) -> String { "\(id.uuidString).json" }
}
