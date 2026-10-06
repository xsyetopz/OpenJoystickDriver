import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct BindingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "binding",
    abstract: CLILocalized.text(
      "cli.binding.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.binding.discussion"
    ),
    subcommands: [BindingListCommand.self, BindingSetCommand.self, BindingClearCommand.self]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
    abstract: CLILocalized.text("cli.binding.list.abstract")
  )

  struct Result: Encodable, Equatable {
    let profile: ProfileSummary
    let bindings: [BindingSummary]
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
      "cli.binding.set.abstract"
    ),
    discussion: BindingCommand.configuration.discussion + "\n\n"
      + CLILocalized.text("cli.binding.set.examples")
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
      CLILocalized.text("cli.binding.set.source"),
      valueName: "source"
    )
  )
  var source: String

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.binding.set.target"),
      valueName: "target"
    )
  )
  var target: String

  @OptionGroup
  var options: BindingOptions

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
      "cli.binding.clear.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.binding.clear.discussion"
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
      CLILocalized.text("cli.binding.clear.sources"),
      valueName: "source"
    )
  )
  var sources: [String] = []

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.binding.clear.all"
      )
    )
  )
  var all = false

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

  func validate() throws {
    guard all != !sources.isEmpty else {
      throw ValidationError(
        CLILocalized.text("cli.binding.clear.usage")
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
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain(result.removed.map { [$0] })
      case .human:
        let message =
          dryRun
          ? CLILocalized.format(
            "cli.binding.clear.dry_run",
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
            "cli.binding.clear.blocks_input",
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
