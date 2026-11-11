import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd binding` command group: list, set and clear the bindings of a profile.
struct BindingCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "binding",
    abstract: CLILocalized.text(
      "cli.binding.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.binding.group.discussion"
    ),
    subcommands: [BindingListCommand.self, BindingSetCommand.self, BindingClearCommand.self]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// One binding in `--json` output.
struct BindingSummary: Encodable, Equatable {
  /// The binding ID.
  let id: String
  /// The source in the `SOURCE` form of `ojd binding set`, such as `button:south`.
  let source: String
  /// The target in the `TARGET` form of `ojd binding set`, such as `key:key-a`.
  let target: String
  /// When the target fires, in kebab-case, such as `hold` or `tap-on-press`.
  let behavior: String

  /// Creates the summary from `binding`; `macros` and `layers` name a `Macro` and a `LayerSet`
  /// target.
  init(_ binding: RemappingBinding, macros: [RemappingMacro] = [], layers: [RemappingLayer] = []) {
    id = binding.id.uuidString
    source = ProfileText.source(binding.source)
    target = ProfileText.destination(binding.destination, macros: macros, layers: layers)
    behavior = binding.behavior.rawValue
  }
}

/// The `ojd binding list` command: prints the bindings of a profile.
struct BindingListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.binding.list.abstract")
  )

  /// One item of the `--json` list: a binding and the profile it came from.
  struct Item: Encodable, Equatable {
    /// The profile that holds the binding.
    let profile: ProfileSummary
    /// The binding ID.
    let id: String
    /// The source in the `SOURCE` form.
    let source: String
    /// The target in the `TARGET` form.
    let target: String
    /// When the target fires.
    let behavior: String

    /// Creates the item from `binding` and the `profile` that holds it.
    init(
      _ binding: RemappingBinding,
      profile: ProfileSummary,
      macros: [RemappingMacro],
      layers: [RemappingLayer]
    ) {
      let summary = BindingSummary(binding, macros: macros, layers: layers)
      self.profile = profile
      id = summary.id
      source = summary.source
      target = summary.target
      behavior = summary.behavior
    }
  }

  /// The profile to list, by ID or name.
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
      switch CLIContext.current.format {
      case .json:
        let profile = ProfileSummary(document, snapshot: snapshot)
        try CLIOutput.json(
          CLIList(
            items: document.bindings.map {
              Item($0, profile: profile, macros: document.macros, layers: document.layers)
            }
          )
        )
      case .plain:
        CLIOutput.plain(
          document.bindings.map {
            BindingSummary($0, macros: document.macros, layers: document.layers)
          }.map {
            [$0.source, $0.target, CommandLineName.kebab($0.behavior)]
          }
        )
      case .human:
        if document.bindings.isEmpty {
          CLIOutput.stderr(
            CLILocalized.format(
              "cli.binding.list.empty",
              document.name
            )
          )
        }
        for binding in document.bindings {
          CLIOutput.stdout(ProfileText.binding(binding, macros: document.macros))
        }
      }
    }
  }
}

extension RemappingProfile {
  /// The layer whose name equals `name`, ignoring case.
  ///
  /// - Throws: ``CLIFailure`` with the not-found code when the profile has no such layer.
  func layer(named name: String) throws -> RemappingLayer {
    let wanted = Self.normalizedName(name)
    guard let layer = layers.first(where: { Self.normalizedName($0.name) == wanted }) else {
      throw CLIFailure(
        .notFound,
        CLILocalized.format("cli.binding.group.layerMissing", self.name, name)
      )
    }
    return layer
  }
}

/// The `ojd binding set` command: binds a source to a target in a profile.
///
/// A source has one binding, so this replaces the binding that the source has and keeps its ID.
struct BindingSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text(
      "cli.binding.set.abstract"
    ),
    discussion: BindingCommand.configuration.discussion + "\n\n"
      + CLILocalized.text("cli.binding.set.examples")
  )

  /// The prefix of a target that runs a macro of the profile by name.
  private static let macroPrefix = "macro:"

  /// The `--json` result of `binding set`.
  struct Result: Encodable, Equatable {
    /// The profile that the command changes.
    let profile: ProfileSummary
    /// The binding that the command writes.
    let binding: BindingSummary
    /// Whether the source already had a binding that this one replaced.
    let replaced: Bool
  }

  /// The profile to change, by ID or name.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The `SOURCE` to bind, such as `button:south` or `axis:left-stick-x:positive`.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.set.source"),
      valueName: "source"
    )
  )
  var source: String

  /// The `TARGET` to send, such as `key:key-a` or `gamepad:button:south`.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.set.target"),
      valueName: "target"
    )
  )
  var target: String

  /// The options that shape how the binding fires.
  @OptionGroup
  var options: BindingOptions

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let source = try parseSource(source)
      let macroName =
        target.hasPrefix(Self.macroPrefix) ? target.dropFirst(Self.macroPrefix.count) : nil
      let layerTarget = RemappingCommandValueParser.layerTarget(target)
      let parsed: RemappingDestination =
        try macroName == nil && layerTarget == nil ? options.destination(target) : .macro(UUID())
      // Reports option errors before the service is contacted.
      _ = try options.binding(source: source, target: parsed, existing: nil)
      let (selector, options) = (profile, options)
      let (binding, replaced, updated, after) = try await ServiceConnection.request { client in
        let (current, _) = try await selector.resolve(with: client)
        let existing = current.bindings.first { $0.source == source }
        let target =
          try macroName.map {
            RemappingDestination.macro(try current.macro(named: String($0)).id)
          }
          ?? layerTarget.map {
            RemappingDestination.layerSet(
              layer: try current.layer(named: $0.name).id,
              mode: $0.mode
            )
          } ?? parsed
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
        binding: BindingSummary(binding, macros: updated.macros, layers: updated.layers),
        replaced: replaced
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain([[result.binding.source, result.binding.target]])
      case .human:
        CLIOutput.success(
          CLILocalized.format(
            "cli.binding.set.done",
            updated.name,
            ProfileText.binding(binding, macros: updated.macros, layers: updated.layers)
          )
        )
      }
    }
  }
}

/// The `ojd binding clear` command: removes the bindings of the given sources, or every binding
/// with `--all`.
///
/// It changes nothing and fails when a source has no binding.
struct BindingClearCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "clear",
    abstract: CLILocalized.text(
      "cli.binding.clear.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.binding.clear.discussion"
    )
  )

  /// The `--json` result of `binding clear`.
  struct Result: Encodable, Equatable {
    /// The profile that the command changes.
    let profile: ProfileSummary
    /// The sources whose bindings were or would be removed.
    let removed: [String]
    /// Whether `--all` is set.
    let all: Bool
    /// Whether `--dry-run` is set, so nothing changes.
    let dryRun: Bool
  }

  /// The profile to change, by ID or name.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The sources whose bindings to remove.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.clear.sources"),
      valueName: "source"
    )
  )
  var sources: [String] = []

  /// `--all`: remove every binding, chord, sequence and layer.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.clear.all"
      )
    )
  )
  var all = false

  /// `-f`, `--force`: skip the confirmation that `--all` asks for.
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

  /// Checks that the command names either `--all` or at least one source, and not both.
  ///
  /// - Throws: ``ValidationError`` otherwise.
  func validate() throws {
    guard all != !sources.isEmpty else {
      throw ValidationError(
        CLILocalized.text("cli.binding.clear.usage")
      )
    }
  }

  /// Runs the command.
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
          .notFound,
          CLILocalized.format(
            "cli.binding.clear.missing",
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
      case .json: try CLIOutput.json(CLIStatus(details: result))
      case .plain: CLIOutput.plain(result.removed.map { [$0] })
      case .human:
        let message =
          dryRun
          ? CLILocalized.format(
            "cli.binding.clear.dryRun",
            current.name,
            result.removed.count
          )
          : CLILocalized.format(
            "cli.binding.clear.done",
            current.name,
            result.removed.count
          )
        if dryRun { CLIOutput.stdout(message) } else { CLIOutput.success(message) }
      }
      if !dryRun, current.suppressesAllControllerInput,
        snapshot.routes.contains(where: { $0.activeProfileID == current.id })
      {
        CLIOutput.stderr(
          CLILocalized.format(
            "cli.binding.clear.blocksInput",
            current.name
          )
        )
      }
    }
  }

  /// `profile` without the bindings of `sources`, or without any binding when `all` is true.
  static func clearing(
    _ profile: RemappingProfile,
    sources: [RemappingSource],
    all: Bool
  ) -> RemappingProfile {
    guard all else {
      return profile.replacing(bindings: profile.bindings.filter { !sources.contains($0.source) })
    }
    return profile.removingAllBindings()
  }
}
