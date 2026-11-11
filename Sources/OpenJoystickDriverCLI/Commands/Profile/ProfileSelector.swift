import ArgumentParser
import Foundation
import OpenJoystickDriverKit

extension ProfileSelector: ExpressibleByArgument {
  /// Reads the profiles from the service and resolves this selector.
  ///
  /// - Throws: ``CLIFailure`` when the service is unreachable, or when no profile or several match.
  func resolve(
    with client: ApplicationServiceClient
  ) async throws -> (RemappingProfile, ApplicationServiceRemappingSnapshotPayload) {
    let snapshot = try await client.getRemappingSnapshot()
    return (try resolve(in: snapshot.profiles), snapshot)
  }
}

/// The shared `PROFILE` argument help.
let profileArgumentHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.profile.group.argument"
  ),
  valueName: "profile"
)

/// One profile in `--json` output.
struct ProfileSummary: Encodable, Equatable {
  /// The profile ID.
  let id: String
  /// The profile name.
  let name: String
  /// The controller model that the profile applies to.
  let controller: String
  /// The app scope: `global` or `app:BUNDLE-ID`.
  let scope: String
  /// Whether the profile is active.
  let active: Bool
  /// The number of bindings.
  let bindings: Int

  /// Describes `profile` as the service snapshot holds it.
  init(_ profile: RemappingProfile, snapshot: ApplicationServiceRemappingSnapshotPayload) {
    id = profile.id.uuidString
    name = profile.name
    controller = deviceIdentity(
      vendorID: Int(profile.device.vendorID),
      productID: Int(profile.device.productID)
    )
    scope = ProfileText.scope(profile.applicationScope)
    active = snapshot.activeProfiles.contains { $0.profileID == profile.id }
    bindings = profile.bindings.count
  }

  /// The `--plain` row of the profile.
  var row: [String] { [id, name, controller, scope, String(active)] }

  /// The human line of the profile, with a marker when it is active.
  var line: String {
    let marker = active ? "  " + CLILocalized.text("cli.profile.group.activeMarker") : ""
    return "\(id)  \(name)  \(controller)  \(scope)\(marker)"
  }
}

extension RemappingProfile {
  /// Validates the profile and turns a validation error into an invalid-profile failure.
  ///
  /// - Throws: ``CLIFailure`` when the profile is not valid.
  func validatedForCLI() throws -> Self {
    do { try validate() } catch {
      throw CLIFailure(
        .invalidProfile,
        CLILocalized.format(
          "cli.profile.group.invalid",
          error.localizedDescription
        )
      )
    }
    return self
  }
}

/// The templates that `ojd profile create --template` accepts.
enum ProfileTemplate: String, CaseIterable, ExpressibleByArgument {
  /// Gyro motion drives a stick of the virtual gamepad.
  case gyroStick = "gyro-stick"
}

extension RemappingGyroStickTemplate.Stick: ExpressibleByArgument {}

extension RemappingVirtualGamepadPolicy: ExpressibleByArgument {
  /// Reads a `--virtual-gamepad` value: `disabled`, `mapped` or `passthrough`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingPhysicalInputPolicy: ExpressibleByArgument {
  /// Reads a `--physical-input` value: `shared` or `exclusive`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingBindingBehavior: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case, such as `tap-on-press`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingResponseCurve: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case, such as `ease-in`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingMotionCalibrationCommand: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case, such as `start`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}
