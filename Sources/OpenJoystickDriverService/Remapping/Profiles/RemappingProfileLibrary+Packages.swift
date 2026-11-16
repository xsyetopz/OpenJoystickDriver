import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {
  /// A profile that an installed mod package ships, with the name of that package.
  struct PackageProfile: Equatable, Sendable {
    /// The profile.
    let profile: RemappingProfile
    /// The name of the package that ships it.
    let packageName: String
  }

  /// The installed mod packages, in `Packages/` beside the library files.
  nonisolated var packagesDirectory: URL {
    directory.appendingPathComponent("Packages", isDirectory: true)
  }

  /// The profiles of the installed packages, which the library serves read-only.
  ///
  /// Only packages that can be used count: a package with an invalid manifest, or one whose
  /// `requires` leaves out the running version, is skipped with a `[Profiles]` line on standard
  /// error. A listed file that cannot be read, decoded, or validated is skipped with the same kind
  /// of line, because the issue kinds of the library only describe the user's files. When two
  /// package profiles share an id or a name (ignoring case), the first one wins, in package-name
  /// order and then manifest order.
  func loadPackageProfiles() -> [PackageProfile] {
    var served: [PackageProfile] = []
    var ids: Set<UUID> = []
    var names: Set<String> = []
    let store = ModPackageStore(directory: packagesDirectory, runningVersion: runningVersion)
    for package in store.list() {
      guard let manifest = package.manifest, package.problem == nil else {
        let reason = package.problem ?? "the manifest cannot be used"
        unsafe fputs("[Profiles] Skipped the package \(package.name): \(reason)\n", unsafe stderr)
        continue
      }
      for fileName in manifest.profiles {
        let url = package.directory.appendingPathComponent("Profiles", isDirectory: true)
          .appendingPathComponent(fileName, isDirectory: false)
        let profile: RemappingProfile
        do {
          // `load(from:)` decodes the file and runs `RemappingProfile.validate()`.
          profile = try RemappingProfileFileStore.load(from: Data(contentsOf: url))
        } catch {
          unsafe fputs(
            "[Profiles] Skipped Profiles/\(fileName) of the package \(package.name): "
              + "\(error)\n",
            unsafe stderr
          )
          continue
        }
        guard !ids.contains(profile.id), !names.contains(Self.normalizedName(profile.name))
        else { continue }
        ids.insert(profile.id)
        names.insert(Self.normalizedName(profile.name))
        served.append(PackageProfile(profile: profile, packageName: package.name))
      }
    }
    return served
  }

  /// The package profiles that the user's profiles do not shadow.
  ///
  /// A user profile with the same id or name wins.
  func servedPackageProfiles(
    shadowedBy user: [RemappingProfile],
    from candidates: [PackageProfile]? = nil
  ) -> [PackageProfile] {
    let ids = Set(user.map(\.id))
    let names = Set(user.map { Self.normalizedName($0.name) })
    return (candidates ?? packageProfiles).filter {
      !ids.contains($0.profile.id) && !names.contains(Self.normalizedName($0.profile.name))
    }
  }

  /// The user's profiles and the served package profiles.
  func allProfiles(
    _ state: RemappingProfileLibraryState,
    packageProfiles candidates: [PackageProfile]? = nil
  ) -> [RemappingProfile] {
    state.profiles
      + servedPackageProfiles(shadowedBy: state.profiles, from: candidates).map(\.profile)
  }

  /// The package that serves each package profile, by profile id.
  func packageProfileSources() throws -> [UUID: String] {
    let loaded = try loadIfNeeded()
    return Dictionary(
      uniqueKeysWithValues: servedPackageProfiles(shadowedBy: loaded.profiles).map {
        ($0.profile.id, $0.packageName)
      }
    )
  }

  /// Refuses a change to a profile that a package serves.
  func requireNotPackageProfile(id: UUID, in state: RemappingProfileLibraryState) throws {
    if servedPackageProfiles(shadowedBy: state.profiles).contains(where: { $0.profile.id == id }) {
      throw RemappingProfileLibraryError.packageProfileReadOnly
    }
  }

  /// Refuses a name that a user profile in `peers` or a served package profile already has.
  func requireNameAvailable(
    _ profile: RemappingProfile,
    among peers: [RemappingProfile],
    in state: RemappingProfileLibraryState
  ) throws {
    let served = servedPackageProfiles(shadowedBy: state.profiles).map(\.profile)
    try validate(profile, in: peers + served)
  }
}
