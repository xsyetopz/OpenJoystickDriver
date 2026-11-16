import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform

/// Stable failures from the locally persisted remapping-profile library.
enum RemappingProfileLibraryError: Error, Equatable, LocalizedError, Sendable {
  /// The profile file or the active profile list is damaged.
  case corruptLibrary
  /// A profile with the name already exists.
  case duplicateName(String)
  /// The profile is invalid, with the validation failure.
  case invalidProfile(RemappingValidationError)
  /// The library would hold more profiles than the limit allows, with the count.
  case profileCountExceeded(Int)
  /// A profile with the ID already exists.
  case profileAlreadyExists(UUID)
  /// No profile has the ID.
  case profileNotFound(UUID)
  /// A Joy-Con pair profile starts only with an explicit pair session.
  case pairProfileRequiresExplicitSession
  /// The profile produces no output; activating it needs `allowEmpty`.
  case profileProducesNoOutput(UUID)
  /// The profile changed since the caller read it.
  case profileUpdateConflict(UUID)
  /// A profile file could not be read.
  case unreadableLibrary
  /// A profile file could not be written.
  case unwritableLibrary
  /// The damaged profile files need repair before a change.
  case profileRecoveryRequired
  /// No damaged-file issue has the ID.
  case profileIssueNotFound(UUID)
  /// The profile comes from a package and cannot be changed.
  case packageProfileReadOnly

  /// The text that explains the failure to a user.
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
    case .profileProducesNoOutput(let id):
      "The remapping profile \(id.uuidString) produces no output; activating it needs "
        + "allowEmpty."
    case .profileUpdateConflict(let id):
      "The remapping profile \(id.uuidString) changed since it was read."
    case .unreadableLibrary: "A remapping profile file could not be read."
    case .unwritableLibrary: "A remapping profile file could not be written."
    case .profileRecoveryRequired:
      "Repair or remove the damaged profile files before changing profiles."
    case .profileIssueNotFound: "The selected damaged profile is no longer current."
    case .packageProfileReadOnly:
      "A profile that comes from an installed package cannot be changed. Duplicate the profile "
        + "and change the copy."
    }
  }
}

/// The single application-service writer for locally authored remapping profiles.
///
/// Each profile is its own `Profiles/<id>.plist` file in the profile-file format, and the active
/// selections are `ActiveProfiles.plist`, both under `directory`. The profiles of the installed
/// packages in `Packages/` are served read-only beside them; they are never written, counted
/// against the profile limit, or deleted.
actor RemappingProfileLibrary {
  /// The most profiles the library holds.
  static let maximumProfileCount = RemappingPayloadLimits.maximumProfileCount
  /// The most bytes of one encoded profile.
  static let maximumEncodedBytes = RemappingPayloadLimits.maximumEncodedBytes
  /// The name of the selections file.
  static let selectionsFileName = "ActiveProfiles.plist"
  /// The name of the file that holds when each profile was last activated.
  static let lastUsedFileName = "LastUsed.plist"

  /// The directory of the library files.
  let directory: URL
  /// The library in memory, nil until it is loaded.
  var library: RemappingProfileLibraryState?
  /// The damaged files that need recovery, by issue ID.
  var profileIssues: [UUID: RecoveryIssue] = [:]
  /// The profiles of the installed packages, read with the library and never written.
  var packageProfiles: [PackageProfile] = []
  /// The OJD version that the `requires` of a package is checked against; nil for the running one.
  let runningVersion: String?
  /// The speech output that tells which voices this Mac has.
  let speechOutput: any RemappingSpeechOutput
  /// The clock that stamps the last use of a profile.
  let clock: @Sendable () -> Date

  /// Creates the library in `directory`.
  init(
    directory: URL = RemappingProfileLibrary.defaultDirectory,
    runningVersion: String? = nil,
    speechOutput: any RemappingSpeechOutput = AVSpeechOutput(),
    clock: @escaping @Sendable () -> Date = Date.init
  ) {
    self.directory = directory
    self.runningVersion = runningVersion
    self.speechOutput = speechOutput
    self.clock = clock
  }

  /// The application data directory.
  static var defaultDirectory: URL { MacOSDataDirectory().url(for: .applicationData) }

  /// The directory of the profile files.
  nonisolated var profilesDirectory: URL {
    directory.appendingPathComponent("Profiles", isDirectory: true)
  }

  /// The URL of the selections file.
  nonisolated var selectionsURL: URL {
    directory.appendingPathComponent(Self.selectionsFileName, isDirectory: false)
  }

  /// Returns the URL of the file of the profile `id`.
  nonisolated func profileURL(_ id: UUID) -> URL {
    profilesDirectory.appendingPathComponent(Self.profileFileName(id), isDirectory: false)
  }

  /// Returns the file name of the profile `id`.
  static func profileFileName(_ id: UUID) -> String { RemappingProfileFileStore.fileName(for: id) }
}
