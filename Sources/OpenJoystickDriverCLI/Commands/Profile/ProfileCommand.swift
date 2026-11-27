import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd profile` command group: create, change, activate and move remapping profiles.
struct ProfileCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "profile",
    abstract: CLILocalized.text(
      "cli.profile.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.group.discussion"
    ),
    subcommands: [
      ProfileListCommand.self, ProfileShowCommand.self, ProfileCreateCommand.self,
      ProfileDuplicateCommand.self, ProfileRenameCommand.self, ProfileDeleteCommand.self,
      ProfileActivateCommand.self, ProfileDeactivateCommand.self, ProfileImportCommand.self,
      ProfileValidateCommand.self, ProfileExportCommand.self, ProfileGetCommand.self,
      ProfileSetCommand.self, ProfileEditCommand.self, ProfileRecoverCommand.self,
      ProfileConvertCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `--json` result of commands that create or change one profile.
struct ProfileResult: Encodable, Equatable {
  /// The profile after the command.
  let profile: ProfileSummary
  /// Whether the command changed the profile.
  let changed: Bool
  var skippedControls: [Control]?
  /// The parts that `profile convert` left out; `nil` for a command that converts nothing.
  var leftOut: [ProfileLeftOut]?
}

/// Prints `result`, with `message` as the human success line.
func printProfile(_ result: ProfileResult, message: String) throws {
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(result)
  case .plain: CLIOutput.plain([result.profile.row])
  case .human: CLIOutput.success(message)
  }
}

/// Resolves `selector`, applies `change` to the profile and saves it, then prints the result with
/// `message` of the saved profile as the human success line; a `change` that leaves the profile as
/// it is saves nothing and prints the unchanged line.
///
/// - Throws: ``CLIFailure`` when the profile cannot be resolved, `change` throws, or the service
///   refuses the update.
func saveProfileChange(
  of selector: ProfileSelector,
  change: (RemappingProfile) throws -> RemappingProfile,
  message: (RemappingProfile) -> String
) async throws {
  let (current, snapshot) = try await selector.resolveFromService()
  let edited = try change(current)
  guard edited != current else {
    try printProfile(
      ProfileResult(profile: ProfileSummary(current, snapshot: snapshot), changed: false),
      message: CLILocalized.text("cli.profile.edit.unchanged")
    )
    return
  }
  let after = try await ServiceConnection.request {
    try await $0.updateRemappingProfile(edited, expectedCurrent: current)
  }
  try printProfile(
    ProfileResult(profile: try savedSummary(edited.id, in: after), changed: true),
    message: message(edited)
  )
}

/// The profile with `id` in `snapshot`; a missing profile means the service changed it meanwhile.
func savedSummary(
  _ id: UUID,
  in snapshot: ApplicationServiceRemappingSnapshotPayload
) throws -> ProfileSummary {
  guard let profile = snapshot.profiles.first(where: { $0.id == id }) else {
    throw CLIFailure(
      .serviceRequestFailed,
      CLILocalized.text(
        "cli.profile.group.vanished"
      )
    )
  }
  return ProfileSummary(profile, snapshot: snapshot)
}

/// The `ojd profile list` command: prints each profile with its ID, name, controller model, app
/// scope and active state, and reports each saved profile that cannot be loaded on stderr.
struct ProfileListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.profile.list.abstract")
  )

  /// The listed profiles. `issues` names each saved profile the service could not load.
  struct Result: Encodable, Equatable {
    /// A saved profile that the service could not load.
    struct Issue: Encodable, Equatable {
      /// The ID of the issue.
      let id: String
      /// The kind of issue.
      let kind: String
      /// The error code of the issue.
      let code: String
      /// What is wrong.
      let message: String
    }

    /// The loaded profiles.
    let profiles: [ProfileSummary]
    /// The profiles that could not be loaded.
    let issues: [Issue]
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let snapshot = try await ServiceConnection.request { try await $0.getRemappingSnapshot() }
      let result = Result(
        profiles: snapshot.profiles.map { ProfileSummary($0, snapshot: snapshot) },
        issues: snapshot.profileIssues.map {
          Result.Issue(
            id: $0.id.uuidString,
            kind: $0.kind.rawValue,
            code: $0.code.rawValue,
            message: $0.message
          )
        }
      )
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIList(items: result.profiles))
      case .plain: CLIOutput.plain(result.profiles.map(\.row))
      case .human:
        if result.profiles.isEmpty {
          CLIOutput.stderr(
            CLILocalized.text(
              "cli.profile.list.empty"
            )
          )
        }
        for profile in result.profiles { CLIOutput.stdout(profile.line) }
      }
      for issue in result.issues {
        CLIOutput.stderr(
          CLILocalized.format(
            "cli.profile.list.issue",
            issue.message
          )
        )
      }
      if !result.issues.isEmpty {
        CLIOutput.stderr(
          CLILocalized.text(
            "cli.profile.list.recoverHint"
          )
        )
      }
    }
  }
}

/// The `ojd profile show` command: prints a profile's settings and bindings.
struct ProfileShowCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.profile.show.abstract"
    )
  )

  /// The `--json` result. `document` is the whole profile, as `ojd profile export` writes it.
  struct Result: Encodable, Equatable {
    /// The summary of the profile.
    let profile: ProfileSummary
    /// The whole profile.
    let document: RemappingProfile
  }

  /// The profile to show.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (document, snapshot) = try await profile.resolveFromService()
      let summary = ProfileSummary(document, snapshot: snapshot)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(Result(profile: summary, document: document))
      case .plain: CLIOutput.plain(ProfileText.details(document).map { [$0] })
      case .human:
        CLIOutput.stdout(summary.line)
        for line in ProfileText.details(document) { CLIOutput.stdout("  \(line)") }
      }
    }
  }
}

extension RemappingProfile {
  /// This profile under another identity and name.
  func copy(id: UUID, name: String) -> Self {
    Self(
      id: id,
      name: name,
      device: device,
      applicationScope: applicationScope,
      outputPolicy: outputPolicy,
      physicalColor: physicalColor,
      motionTuning: motionTuning,
      gyroOutput: gyroOutput,
      joyConPair: joyConPair,
      pointerSpeed: pointerSpeed,
      stickMappings: stickMappings,
      triggerMappings: triggerMappings,
      touchMappings: touchMappings,
      bindings: bindings,
      chords: chords,
      sequences: sequences,
      layers: layers
    )
  }
}
