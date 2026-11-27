public import ArgumentParser
import Foundation
public import OpenJoystickDriverKit

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

  /// Connects to the service for one request and resolves this selector.
  ///
  /// - Throws: ``CLIFailure`` when the service is unreachable, or when no profile or several match.
  func resolveFromService() async throws -> (
    RemappingProfile, ApplicationServiceRemappingSnapshotPayload
  ) {
    let selector = self
    return try await ServiceConnection.request { try await selector.resolve(with: $0) }
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
  case keyboardNavigation = "keyboard-navigation"
  case mouseClicks = "mouse-clicks"
}

extension RemappingGyroStickTemplate.Stick: ExpressibleByArgument {}

/// An enumeration that the command line spells in kebab-case: a raw value of `tapOnPress` is
/// `tap-on-press`.
protocol KebabCaseArgument: ExpressibleByArgument, CaseIterable, RawRepresentable
where RawValue == String {}

extension KebabCaseArgument {
  /// Reads the case whose raw value spells `argument` in kebab-case.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingVirtualGamepadPolicy: KebabCaseArgument {}

extension RemappingPhysicalInputPolicy: KebabCaseArgument {}

extension RemappingBindingBehavior: KebabCaseArgument {}

extension RemappingResponseCurve: KebabCaseArgument {}

extension RemappingMotionCalibrationCommand: KebabCaseArgument {}
