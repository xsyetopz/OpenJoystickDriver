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

/// The `ojd profile create` command: creates an empty, inactive profile for one controller model.
struct ProfileCreateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "create",
    abstract: CLILocalized.text(
      "cli.profile.create.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.create.discussion"
    ) + "\n\n" + CLILocalized.text("cli.profile.create.examples")
  )

  /// The name of the profile.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.group.name"),
      valueName: "name"
    )
  )
  var name: String

  /// `--controller`: the controller model as `VVVV:PPPP`, or the ID of a connected controller.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.controller"
      ),
      valueName: "controller"
    )
  )
  var controller: ControllerSelector

  /// `--app`: the bundle ID of an app that the profile applies to, repeated for more apps;
  /// without it the profile applies in every app.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.app"
      ),
      valueName: "app-id"
    )
  )
  var app: [String] = []

  /// `--virtual-gamepad`: `disabled` publishes no virtual gamepad, `mapped` sends only the bound
  /// controls, and `passthrough` also sends the unbound controls.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.virtualGamepad"
      )
    )
  )
  var virtualGamepad: RemappingVirtualGamepadPolicy = .passthrough

  /// `--physical-input`: `shared` lets the profile emit input while the native physical input stays
  /// visible, and `exclusive` requires confirmed exclusive ownership of the controller.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "platform.macos.cli.profile.create.physicalInput"
      )
    )
  )
  var physicalInput: RemappingPhysicalInputPolicy = .shared

  /// `--template`: starts the profile from a template instead of empty.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.create.template"),
      valueName: "template"
    )
  )
  var template: ProfileTemplate?

  /// `--stick`: the stick that the `gyro-stick` template drives.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.create.stick"),
      valueName: "stick"
    )
  )
  var stick: RemappingGyroStickTemplate.Stick?

  /// `--activation`: the control that must be held for gyro output; without it gyro output is
  /// always on.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.create.activation"),
      valueName: "control"
    )
  )
  var activation: String?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      guard template == .gyroStick || (stick == nil && activation == nil) else {
        throw CLIFailure.usage(CLILocalized.text("cli.profile.create.templateRequired"))
      }
      let activationSource = try activation.map(parseSource)
      let selector = controller
      let scope = app.isEmpty ? RemappingApplicationScope.global : .application(appIDs: app)
      let policy = RemappingOutputPolicy(
        virtualGamepad: virtualGamepad,
        physicalInput: physicalInput
      )
      let name = name
      let (created, skippedControls, snapshot) = try await ServiceConnection.request { client in
        let device: RemappingDeviceScope
        switch selector.reference {
        case .model(let model):
          device = RemappingDeviceScope(vendorID: model.vendorID, productID: model.productID)
        case .session, .port:
          let found = try await selector.resolve(with: client)
          device = RemappingDeviceScope(vendorID: found.vendorID, productID: found.productID)
        }
        let profile: RemappingProfile
        var skipped: [Control]?
        let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
        let capabilities = ProtocolDriverRegistry().profileCapabilities(for: model) ?? .unknown
        func fromBindings(_ bindings: RemappingBindingTemplate) throws -> RemappingProfile {
          let made = bindings.profile(
            name: name,
            device: device,
            applicationScope: scope,
            outputPolicy: policy,
            capabilities: capabilities
          )
          skipped = made.skipped
          return try made.profile.validatedForCLI()
        }
        switch template {
        case .keyboardNavigation: profile = try fromBindings(.keyboardNavigation)
        case .mouseClicks: profile = try fromBindings(.mouseClicks)
        case .gyroStick:
          do {
            profile = try RemappingGyroStickTemplate.profile(
              name: name,
              device: device,
              applicationScope: scope,
              stick: stick ?? .right,
              activation: activationSource,
              capabilities: capabilities
            ).validatedForCLI()
          } catch RemappingGyroStickTemplate.Failure.noMotionSensor(let model) {
            throw CLIFailure(
              .invalidProfile,
              CLILocalized.format("cli.profile.create.noMotion", model.description)
            )
          }
        case nil:
          profile = try RemappingProfile(
            name: name,
            device: device,
            applicationScope: scope,
            outputPolicy: policy,
            bindings: []
          ).validatedForCLI()
        }
        return (profile, skipped, try await client.createRemappingProfile(profile))
      }
      var message = CLILocalized.format(
        "cli.profile.create.done",
        created.name,
        created.id.uuidString
      )
      if let skippedControls, !skippedControls.isEmpty {
        message += "\n" + CLILocalized.format(
          "cli.profile.create.skipped",
          skippedControls.map(\.rawValue).joined(separator: ", ")
        )
      }
      try printProfile(
        ProfileResult(
          profile: try savedSummary(created.id, in: snapshot),
          changed: true,
          skippedControls: skippedControls
        ),
        message: message
      )
    }
  }
}

/// The `ojd profile duplicate` command: copies a profile under another name.
///
/// The copy is inactive.
struct ProfileDuplicateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "duplicate",
    abstract: CLILocalized.text(
      "cli.profile.duplicate.abstract"
    )
  )

  /// The profile to copy.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The name of the copy.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.duplicate.name"),
      valueName: "new-name"
    )
  )
  var name: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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

/// The `ojd profile rename` command: gives a profile another name of 1 to 80 characters.
struct ProfileRenameCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "rename",
    abstract: CLILocalized.text("cli.profile.rename.abstract")
  )

  /// The profile to rename.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The name to give.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.rename.name"),
      valueName: "new-name"
    )
  )
  var name: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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

/// The `ojd profile delete` command: deletes a profile, which stops applying if it is active.
struct ProfileDeleteCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "delete",
    abstract: CLILocalized.text("cli.profile.delete.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.delete.discussion"
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The profile that the command deletes.
    let deleted: ProfileSummary
    /// Whether `--dry-run` is set, so nothing is deleted.
    let dryRun: Bool
  }

  /// The profile to delete.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// `-n`, `--dry-run`: print what would change and change nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.dryRun")
    )
  )
  var dryRun = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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
              "cli.profile.delete.dryRun",
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
