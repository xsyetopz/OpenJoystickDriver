import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ProfileCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "profile",
    abstract: CLILocalized.text(
      "cli.profile.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.discussion"
    ),
    subcommands: [
      ProfileListCommand.self, ProfileShowCommand.self, ProfileCreateCommand.self,
      ProfileDuplicateCommand.self, ProfileRenameCommand.self, ProfileDeleteCommand.self,
      ProfileActivateCommand.self, ProfileDeactivateCommand.self, ProfileImportCommand.self,
      ProfileValidateCommand.self, ProfileExportCommand.self, ProfileGetCommand.self,
      ProfileSetCommand.self, ProfileEditCommand.self, ProfileRecoverCommand.self,
    ]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `--json` result of commands that create or change one profile.
struct ProfileResult: Encodable, Equatable {
  let profile: ProfileSummary
  let changed: Bool
}

/// Prints `result`, with `message` as the human success line.
func printProfile(_ result: ProfileResult, message: String) throws {
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(result)
  case .plain: CLIOutput.plain([result.profile.row])
  case .human: CLIOutput.success(message)
  }
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
        "cli.profile.vanished"
      )
    )
  }
  return ProfileSummary(profile, snapshot: snapshot)
}

struct ProfileListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.profile.list.abstract")
  )

  /// The listed profiles. `issues` names each saved profile the service could not load.
  struct Result: Encodable, Equatable {
    struct Issue: Encodable, Equatable {
      let id: String
      let kind: String
      let message: String
    }

    let profiles: [ProfileSummary]
    let issues: [Issue]
  }

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let snapshot = try await ServiceConnection.request { try await $0.getRemappingSnapshot() }
      let result = Result(
        profiles: snapshot.profiles.map { ProfileSummary($0, snapshot: snapshot) },
        issues: snapshot.profileIssues.map {
          Result.Issue(id: $0.id.uuidString, kind: $0.kind.rawValue, message: $0.message)
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
            "cli.profile.list.recover_hint"
          )
        )
      }
    }
  }
}

struct ProfileShowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.profile.show.abstract"
    )
  )

  /// The `--json` result. `document` is the whole profile, as `ojd profile export` writes it.
  struct Result: Encodable, Equatable {
    let profile: ProfileSummary
    let document: RemappingProfile
  }

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = profile
      let (document, snapshot) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
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

struct ProfileCreateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "create",
    abstract: CLILocalized.text(
      "cli.profile.create.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.create.discussion"
    ) + "\n\n" + CLILocalized.text("cli.profile.create.examples")
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.name"),
      valueName: "name"
    )
  )
  var name: String

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.controller"
      ),
      valueName: "controller"
    )
  )
  var controller: ControllerSelector

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.app"
      ),
      valueName: "bundle-id"
    )
  )
  var app: String?

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.virtual_gamepad"
      )
    )
  )
  var virtualGamepad: RemappingVirtualGamepadPolicy = .passthrough

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.physical_input"
      )
    )
  )
  var physicalInput: RemappingPhysicalInputPolicy = .shared

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = controller
      let scope = app.map { RemappingApplicationScope.application(bundleIdentifier: $0) } ?? .global
      let policy = RemappingOutputPolicy(
        virtualGamepad: virtualGamepad,
        physicalInput: physicalInput
      )
      let name = name
      let (created, snapshot) = try await ServiceConnection.request { client in
        let device: RemappingDeviceScope
        switch selector.kind {
        case .model(let vendorID, let productID):
          device = RemappingDeviceScope(vendorID: vendorID, productID: productID)
        case .id:
          let found = try await selector.resolve(with: client)
          device = RemappingDeviceScope(vendorID: found.vendorID, productID: found.productID)
        }
        let profile = try RemappingProfile(
          name: name,
          device: device,
          applicationScope: scope,
          outputPolicy: policy,
          bindings: []
        ).validatedForCLI()
        return (profile, try await client.createRemappingProfile(profile))
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(created.id, in: snapshot), changed: true),
        message: CLILocalized.format(
          "cli.profile.create.done",
          created.name,
          created.id.uuidString
        )
      )
    }
  }
}

struct ProfileDuplicateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "duplicate",
    abstract: CLILocalized.text(
      "cli.profile.duplicate.abstract"
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.duplicate.name"),
      valueName: "new-name"
    )
  )
  var name: String

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let (selector, name) = (profile, name)
      let (copy, snapshot) = try await ServiceConnection.request { client in
        let (original, _) = try await selector.resolve(with: client)
        let copy = try original.copy(id: UUID(), name: name).validatedForCLI()
        return (copy, try await client.createRemappingProfile(copy))
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(copy.id, in: snapshot), changed: true),
        message: CLILocalized.format(
          "cli.profile.duplicate.done",
          copy.name,
          copy.id.uuidString
        )
      )
    }
  }
}

struct ProfileRenameCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "rename",
    abstract: CLILocalized.text("cli.profile.rename.abstract")
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.rename.name"),
      valueName: "new-name"
    )
  )
  var name: String

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let (selector, name) = (profile, name)
      let (renamed, snapshot) = try await ServiceConnection.request { client in
        let (current, _) = try await selector.resolve(with: client)
        let renamed = try current.replacing(name: name).validatedForCLI()
        return (renamed, try await client.updateRemappingProfile(renamed, expectedCurrent: current))
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(renamed.id, in: snapshot), changed: true),
        message: CLILocalized.format("cli.profile.rename.done", renamed.name)
      )
    }
  }
}

struct ProfileDeleteCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete",
    abstract: CLILocalized.text("cli.profile.delete.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.delete.discussion"
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    let deleted: ProfileSummary
    let dryRun: Bool
  }

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force"))
  )
  var force = false

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.dry_run")
    )
  )
  var dryRun = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = profile
      let client = try await ServiceConnection.open()
      defer { client.disconnect() }
      let timeout = CLIContext.current.requestTimeout
      let (target, snapshot) = try await ServiceConnection.withDeadline(seconds: timeout) {
        try await selector.resolve(with: client)
      }
      let summary = ProfileSummary(target, snapshot: snapshot)
      if !dryRun {
        try CLITerminal.confirm(
          CLILocalized.format(
            "cli.profile.delete.confirm",
            target.name
          ),
          force: force
        )
        _ = try await ServiceConnection.withDeadline(seconds: timeout) {
          try await client.deleteRemappingProfile(id: target.id)
        }
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIStatus(details: Result(deleted: summary, dryRun: dryRun)))
      case .plain: CLIOutput.plain([summary.row])
      case .human:
        if dryRun {
          CLIOutput.stdout(
            CLILocalized.format(
              "cli.profile.delete.dry_run",
              target.name
            )
          )
        } else {
          CLIOutput.success(
            CLILocalized.format("cli.profile.delete.done", target.name)
          )
        }
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
