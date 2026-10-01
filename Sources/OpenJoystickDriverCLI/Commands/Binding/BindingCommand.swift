import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct BindingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "binding",
    abstract: CLILocalized.text(
      "cli.binding.abstract",
      "List, set, and clear the bindings of a remapping profile."
    ),
    discussion: CLILocalized.text(
      "cli.binding.discussion",
      "A binding sends a TARGET when a controller SOURCE is used.\n\n"
        + "SOURCE: button:NAME, dpad:DIRECTION, axis:NAME[:negative|positive], "
        + "trigger:NAME:STAGE, motion:lean:DIRECTION, touch:SURFACE:contact, "
        + "touch:SURFACE:grid:COLUMNS:ROWS:COLUMN:ROW, or "
        + "touch:SURFACE:swipe:DIRECTION:DISTANCE.\n\n"
        + "TARGET: key:KEY[:mods=command,control,option,shift], mouse:BUTTON, move:x|y, "
        + "scroll:x|y, gamepad:button:NAME, gamepad:dpad:DIRECTION, gamepad:axis:NAME, or "
        + "physical:... for rumble, lights, and adaptive triggers.\n\n"
        + "'ojd profile show' prints bindings in these forms. Edit chords, sequences, and "
        + "layers with 'ojd profile edit'."
    ),
    subcommands: [BindingListCommand.self, BindingSetCommand.self, BindingClearCommand.self]
  )

  @OptionGroup
  var global: GlobalOptions
}

/// One binding in `--json` output.
struct BindingSummary: Encodable, Equatable {
  let id: String
  let source: String
  let target: String
  let behavior: String

  init(_ binding: RemappingBinding) {
    id = binding.id.uuidString
    source = ProfileText.source(binding.source)
    target = ProfileText.destination(binding.destination)
    behavior = binding.behavior.rawValue
  }
}

struct BindingListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.binding.list.abstract", "List a profile's bindings.")
  )

  struct Result: Encodable, Equatable {
    let profile: ProfileSummary
    let bindings: [BindingSummary]
  }

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = profile
      let (document, snapshot) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            profile: ProfileSummary(document, snapshot: snapshot),
            bindings: document.bindings.map(BindingSummary.init)
          )
        )
      case .plain:
        CLIOutput.plain(
          document.bindings.map(BindingSummary.init).map { [$0.source, $0.target, $0.behavior] }
        )
      case .human:
        if document.bindings.isEmpty {
          CLIOutput.stderr(
            CLILocalized.format(
              "cli.binding.list.empty",
              "'%@' has no bindings. Add one with 'ojd binding set'.",
              document.name
            )
          )
        }
        for binding in document.bindings { CLIOutput.stdout(ProfileText.binding(binding)) }
      }
    }
  }
}

struct BindingSetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text(
      "cli.binding.set.abstract",
      "Bind a controller source to a target, replacing the source's current binding."
    ),
    discussion: BindingCommand.configuration.discussion
  )

  struct Result: Encodable, Equatable {
    let profile: ProfileSummary
    let binding: BindingSummary
    let replaced: Bool
  }

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.set.source", "The controller control, such as button:south."),
      valueName: "source"
    )
  )
  var source: String

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.set.target", "What it sends, such as key:space."),
      valueName: "target"
    )
  )
  var target: String

  @OptionGroup
  var options: BindingOptions

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let source = try parseSource(source)
      let target = try parseTarget(target)
      // Reports option errors before the service is contacted.
      _ = try options.binding(source: source, target: target, existing: nil)
      let (selector, options) = (profile, options)
      let (binding, replaced, updated, after) = try await ServiceConnection.request { client in
        let (current, _) = try await selector.resolve(with: client)
        let existing = current.bindings.first { $0.source == source }
        let binding = try options.binding(source: source, target: target, existing: existing)
        let bindings = current.bindings.map { $0.source == source ? binding : $0 }
        let updated = try current.replacing(
          bindings: existing == nil ? current.bindings + [binding] : bindings
        ).validatedForCLI()
        let after = try await client.updateRemappingProfile(updated, expectedCurrent: current)
        return (binding, existing != nil, updated, after)
      }
      let result = Result(
        profile: try savedSummary(updated.id, in: after),
        binding: BindingSummary(binding),
        replaced: replaced
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain([[result.binding.source, result.binding.target]])
      case .human:
        CLIOutput.success(
          CLILocalized.format(
            "cli.binding.set.done",
            "'%@' now binds %@.",
            updated.name,
            ProfileText.binding(binding)
          )
        )
      }
    }
  }
}

struct BindingClearCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clear",
    abstract: CLILocalized.text(
      "cli.binding.clear.abstract",
      "Remove the bindings of the given sources, or every binding."
    ),
    discussion: CLILocalized.text(
      "cli.binding.clear.discussion",
      "--all also removes the profile's chords, sequences, and layers, and asks for "
        + "confirmation on a terminal; it needs --force otherwise. Stick, trigger, touch, motion, "
        + "and output settings stay."
    )
  )

  struct Result: Encodable, Equatable {
    let profile: ProfileSummary
    let removed: [String]
    let all: Bool
    let dryRun: Bool
  }

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.clear.sources", "The sources whose bindings to remove."),
      valueName: "source"
    )
  )
  var sources: [String] = []

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.clear.all",
        "Remove every binding, chord, sequence, and layer."
      )
    )
  )
  var all = false

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force", "Do not ask for confirmation."))
  )
  var force = false

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.dry_run", "Print what would change, and change nothing.")
    )
  )
  var dryRun = false

  @OptionGroup
  var global: GlobalOptions

  func validate() throws {
    guard all != !sources.isEmpty else {
      throw ValidationError(
        CLILocalized.text("cli.binding.clear.usage", "Give one or more sources, or --all.")
      )
    }
  }

  func run() async throws {
    try await global.run {
      let parsed = try sources.map(parseSource)
      let (selector, all) = (profile, all)
      let client = try await ServiceConnection.open()
      defer { client.disconnect() }
      let timeout = CLIContext.current.requestTimeout
      var (current, snapshot) = try await ServiceConnection.withDeadline(seconds: timeout) {
        try await selector.resolve(with: client)
      }
      let removing = all ? current.bindings.map(\.source) : parsed
      if !all,
        let missing = parsed.first(where: { source in
          !current.bindings.contains { $0.source == source }
        })
      {
        throw CLIFailure(
          .failure,
          CLILocalized.format(
            "cli.binding.clear.missing",
            "'%@' has no binding for %@. Nothing changed.",
            current.name,
            ProfileText.source(missing)
          )
        )
      }
      if !dryRun {
        if all {
          try CLITerminal.confirm(
            CLILocalized.format(
              "cli.binding.clear.confirm",
              "Remove every binding, chord, sequence, and layer from '%@'?",
              current.name
            ),
            force: force
          )
        }
        let updated = try Self.clearing(current, sources: parsed, all: all).validatedForCLI()
        let expected = current
        snapshot = try await ServiceConnection.withDeadline(seconds: timeout) {
          try await client.updateRemappingProfile(updated, expectedCurrent: expected)
        }
        current = updated
      }
      let result = Result(
        profile: try savedSummary(current.id, in: snapshot),
        removed: removing.map(ProfileText.source),
        all: all,
        dryRun: dryRun
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain(result.removed.map { [$0] })
      case .human:
        let message =
          dryRun
          ? CLILocalized.format(
            "cli.binding.clear.dry_run",
            "Would remove %lld bindings from '%@'.",
            result.removed.count,
            current.name
          )
          : CLILocalized.format(
            "cli.binding.clear.done",
            "Removed %lld bindings from '%@'.",
            result.removed.count,
            current.name
          )
        if dryRun { CLIOutput.stdout(message) } else { CLIOutput.success(message) }
      }
      if !dryRun, current.suppressesAllControllerInput,
        snapshot.routes.contains(where: { $0.activeProfileID == current.id })
      {
        CLIOutput.stderr(
          CLILocalized.format(
            "cli.binding.clear.blocks_input",
            "'%@' is active on a connected controller and now blocks all of its input. "
              + "Add a binding with 'ojd binding set', or stop the profile with "
              + "'ojd profile deactivate'.",
            current.name
          )
        )
      }
    }
  }

  static func clearing(
    _ profile: RemappingProfile,
    sources: [RemappingSource],
    all: Bool
  ) -> RemappingProfile {
    guard all else {
      return profile.replacing(bindings: profile.bindings.filter { !sources.contains($0.source) })
    }
    return profile.replacing(bindings: [], chords: [], sequences: [], layers: [])
  }
}
