import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `PROFILE` argument: a profile UUID, or a profile name matched exactly but without regard
/// to case.
struct ProfileSelector: ExpressibleByArgument, Equatable, Sendable {
  /// The argument as typed.
  let text: String

  /// Parses `argument`; fails when it is empty.
  init?(argument: String) {
    guard !argument.isEmpty else { return nil }
    text = argument
  }

  /// The one profile this selector names.
  ///
  /// - Throws: ``CLIFailure`` with exit code 1 when no profile or several profiles match.
  func resolve(in profiles: [RemappingProfile]) throws -> RemappingProfile {
    if let id = UUID(uuidString: text), let profile = profiles.first(where: { $0.id == id }) {
      return profile
    }
    let matches = profiles.filter { $0.name.caseInsensitiveCompare(text) == .orderedSame }
    if matches.count == 1, let profile = matches.first { return profile }
    guard matches.isEmpty else {
      let message = CLILocalized.plural(
        "cli.profile.group.selectorAmbiguous",
        text,
        matches.count
      )
      let lines = matches.map { "  \($0.id.uuidString)  \($0.name)" }
      throw CLIFailure(.notFound, ([message] + lines).joined(separator: "\n"))
    }
    throw CLIFailure(
      .notFound,
      CLILocalized.format(
        "cli.profile.group.selectorNotFound",
        text
      )
    )
  }

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

  /// Checks that the controller reports the trigger or stick of the pointer speed.
  ///
  /// The model has no capability data, so this runs where the profile enters: `profile set` and
  /// `profile import`. A controller that the catalog does not know is not checked.
  ///
  /// - Throws: ``CLIFailure`` with the invalid profile code when the controller lacks the driver.
  func checkingPointerSpeedDriver() throws -> Self {
    if let speed = pointerSpeed,
      let capabilities = ProtocolDriverRegistry().profileCapabilities(
        for: ControllerModelID(vendorID: device.vendorID, productID: device.productID)
      ), !speed.isSupported(by: capabilities)
    {
      throw CLIFailure(
        .invalidProfile,
        CLILocalized.format(
          "cli.profile.group.invalid",
          RemappingValidationError.unsupportedPointerSpeedDriver.localizedDescription
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
