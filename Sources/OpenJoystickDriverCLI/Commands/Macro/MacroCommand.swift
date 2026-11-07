import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd macro` command group: list, show, set and remove the macros of a profile.
struct MacroCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "macro",
    abstract: CLILocalized.text("cli.macro.group.abstract"),
    subcommands: [
      MacroListCommand.self, MacroShowCommand.self, MacroSetCommand.self, MacroRemoveCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

extension RemappingProfile {
  /// The macro whose name equals `name`, ignoring case.
  ///
  /// - Throws: ``CLIFailure`` with the not-found code when the profile has no such macro.
  func macro(named name: String) throws -> RemappingMacro {
    let wanted = Self.normalizedName(name)
    guard let macro = macros.first(where: { Self.normalizedName($0.name) == wanted }) else {
      throw CLIFailure(
        .notFound,
        CLILocalized.format("cli.macro.group.missing", self.name, name)
      )
    }
    return macro
  }
}

/// One macro in `--json` output, with steps in the `--step` form.
struct MacroSummary: Encodable, Equatable {
  /// The `repeat` text of a macro that runs until the source is released.
  static let whileHeld = "while-held"

  /// The macro ID.
  let id: String
  /// The macro name.
  let name: String
  /// A pass count, or `while-held`.
  let repeatMode: String
  /// What a press of the source does while the macro runs; JSON carries the document value.
  let whileRunning: RemappingMacroWhileRunning
  /// Whether releasing the source stops the macro.
  let interruptOnRelease: Bool
  /// The steps in order, such as `tap:key:key-a`.
  let steps: [String]

  /// The JSON keys; `repeat` is the key of the profile document.
  private enum CodingKeys: String, CodingKey {
    /// The keys that match the property names.
    case id, name, whileRunning, interruptOnRelease, steps
    /// The `repeat` key.
    case repeatMode = "repeat"
  }

  /// Creates the summary from `macro`.
  init(_ macro: RemappingMacro) {
    id = macro.id.uuidString
    name = macro.name
    switch macro.repeatMode {
    case .count(let count): repeatMode = String(count)
    case .whileHeld: repeatMode = Self.whileHeld
    }
    whileRunning = macro.whileRunning
    interruptOnRelease = macro.interruptOnRelease
    steps = macro.steps.map(Self.text)
  }

  /// A step in its `--step` form.
  private static func text(_ step: RemappingMacroStep) -> String {
    switch step {
    case .tap(let destination): "tap:\(ProfileText.destination(destination))"
    case .press(let destination): "press:\(ProfileText.destination(destination))"
    case .release(let destination): "release:\(ProfileText.destination(destination))"
    case .wait(let durationMs): "wait:\(durationMs)"
    case .chord(let destinations, let holdMs):
      "chord:\(holdMs):" + destinations.map { ProfileText.destination($0) }.joined(separator: "+")
    }
  }

  /// Parses one `--step` value.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when `text` is not a step.
  static func step(_ text: String) throws -> RemappingMacroStep {
    let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let invalid = CLIFailure.usage(CLILocalized.format("cli.macro.group.stepInvalid", text))
    guard parts.count == 2 else { throw invalid }
    let rest = String(parts[1])
    switch parts[0] {
    case "tap": return .tap(try parseTarget(rest))
    case "press": return .press(try parseTarget(rest))
    case "release": return .release(try parseTarget(rest))
    case "wait":
      guard let milliseconds = Double(rest), milliseconds.isFinite else { throw invalid }
      return .wait(durationMs: milliseconds)
    case "chord":
      let chord = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard chord.count == 2, let milliseconds = Double(chord[0]), milliseconds.isFinite else {
        throw invalid
      }
      return .chord(
        destinations: try chord[1].split(separator: "+", omittingEmptySubsequences: false)
          .map { try parseTarget(String($0)) },
        holdMs: milliseconds
      )
    default: throw invalid
    }
  }
}

extension RemappingMacroWhileRunning: ExpressibleByArgument {
  /// Reads a `--while-running` value: `ignore` or `restart`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

/// The `ojd macro list` command: prints the macros of a profile.
struct MacroListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.macro.list.abstract")
  )

  /// One item of the `--json` list: a macro and the profile it came from.
  struct Item: Encodable, Equatable {
    /// The profile that holds the macro.
    let profile: ProfileSummary
    /// The macro.
    let macro: MacroSummary
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
      let macros = document.macros.map(MacroSummary.init)
      switch CLIContext.current.format {
      case .json:
        let profile = ProfileSummary(document, snapshot: snapshot)
        try CLIOutput.json(CLIList(items: macros.map { Item(profile: profile, macro: $0) }))
      case .plain: CLIOutput.plain(macros.map { [$0.name, $0.repeatMode, "\($0.steps.count)"] })
      case .human:
        if macros.isEmpty {
          CLIOutput.stderr(CLILocalized.format("cli.macro.list.empty", document.name))
        }
        for macro in macros {
          CLIOutput.stdout("\(macro.name)  repeat:\(macro.repeatMode)  steps:\(macro.steps.count)")
        }
      }
    }
  }
}

/// The `--json` result of `macro show` and `macro set`.
struct MacroResult: Encodable, Equatable {
  /// The profile that holds the macro.
  let profile: ProfileSummary
  /// The macro.
  let macro: MacroSummary
  /// Whether `macro set` replaced a macro of the same name; nil for `macro show`.
  let replaced: Bool?
}

/// Prints a macro in the format of the command.
private func printMacro(_ result: MacroResult) throws {
  let macro = result.macro
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(result)
  case .plain: CLIOutput.plain(macro.steps.map { [macro.name, $0] })
  case .human:
    let whileRunning = CommandLineName.kebab(macro.whileRunning.rawValue)
    CLIOutput.stdout(
      "\(macro.name)  repeat:\(macro.repeatMode)  while-running:\(whileRunning)"
        + "  interrupt-on-release:\(macro.interruptOnRelease)"
    )
    for step in macro.steps { CLIOutput.stdout("  \(step)") }
  }
}

/// The `ojd macro show` command: prints one macro with its steps.
struct MacroShowCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text("cli.macro.show.abstract")
  )

  /// The profile that holds the macro, by ID or name.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The macro name.
  @Argument(help: ArgumentHelp(CLILocalized.text("cli.macro.group.name"), valueName: "name"))
  var name: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (selector, name) = (profile, name)
      let (document, snapshot) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      try printMacro(
        MacroResult(
          profile: ProfileSummary(document, snapshot: snapshot),
          macro: MacroSummary(try document.macro(named: name)),
          replaced: nil
        )
      )
    }
  }
}

/// The `ojd macro set` command: creates a macro, or replaces the macro of the same name and keeps
/// its ID.
struct MacroSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.macro.set.abstract")
  )

  /// The profile to change, by ID or name.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The macro name.
  @Argument(help: ArgumentHelp(CLILocalized.text("cli.macro.group.name"), valueName: "name"))
  var name: String

  /// `--step`: one step, in order; repeat the option for more.
  @Option(
    name: .customLong("step"),
    help: ArgumentHelp(CLILocalized.text("cli.macro.set.step"), valueName: "step")
  )
  var steps: [String]

  /// `--repeat`: a pass count or `while-held`.
  @Option(
    name: .customLong("repeat"),
    help: ArgumentHelp(CLILocalized.text("cli.macro.set.repeat"), valueName: "count")
  )
  var repeatMode: String?

  /// `--while-running`: what a press of the source does while the macro runs.
  @Option(help: ArgumentHelp(CLILocalized.text("cli.macro.set.whileRunning")))
  var whileRunning: RemappingMacroWhileRunning?

  /// `--interrupt-on-release` or `--no-interrupt-on-release`: whether releasing the source stops
  /// the macro.
  @Flag(
    inversion: .prefixedNo,
    help: ArgumentHelp(CLILocalized.text("cli.macro.set.interrupt"))
  )
  var interruptOnRelease: Bool?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let parsedSteps = try steps.map(MacroSummary.step)
      let parsedRepeat = try repeatMode.map { text -> RemappingMacroRepeat in
        if text == MacroSummary.whileHeld { return .whileHeld }
        guard let count = Int(text) else {
          throw CLIFailure.usage(CLILocalized.format("cli.macro.set.repeatInvalid", text))
        }
        return .count(count)
      }
      let (selector, name, whileRunning, interrupt) =
        (profile, name, whileRunning, interruptOnRelease)
      let (macro, replaced, updated, after) = try await ServiceConnection.request { client in
        let (current, _) = try await selector.resolve(with: client)
        let existing = try? current.macro(named: name)
        let macro = RemappingMacro(
          id: existing?.id ?? UUID(),
          name: name,
          steps: parsedSteps,
          repeatMode: parsedRepeat ?? existing?.repeatMode ?? .count(1),
          whileRunning: whileRunning ?? existing?.whileRunning ?? .ignore,
          interruptOnRelease: interrupt ?? existing?.interruptOnRelease ?? false
        )
        let updated = try current.replacing(
          macros: existing == nil
            ? current.macros + [macro] : current.macros.map { $0.id == macro.id ? macro : $0 }
        ).validatedForCLI()
        let after = try await client.updateRemappingProfile(updated, expectedCurrent: current)
        return (macro, existing != nil, updated, after)
      }
      let result = MacroResult(
        profile: try savedSummary(updated.id, in: after),
        macro: MacroSummary(macro),
        replaced: replaced
      )
      if case .human = CLIContext.current.format {
        CLIOutput.success(CLILocalized.format("cli.macro.set.done", updated.name, macro.name))
      } else {
        try printMacro(result)
      }
    }
  }
}

/// The `ojd macro remove` command: removes a macro, which fails while a binding runs it.
struct MacroRemoveCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "remove",
    abstract: CLILocalized.text("cli.macro.remove.abstract")
  )

  /// The `--json` result of `macro remove`.
  struct Result: Encodable, Equatable {
    /// The profile that the command changes.
    let profile: ProfileSummary
    /// The name of the removed macro.
    let removed: String
  }

  /// The profile to change, by ID or name.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The macro name.
  @Argument(help: ArgumentHelp(CLILocalized.text("cli.macro.group.name"), valueName: "name"))
  var name: String

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (selector, name, force) = (profile, name, force)
      let client = try await ServiceConnection.open()
      defer { client.disconnect() }
      let timeout = CLIContext.current.requestTimeout
      let (current, _) = try await ServiceConnection.withDeadline(seconds: timeout) {
        try await selector.resolve(with: client)
      }
      let macro = try current.macro(named: name)
      try CLITerminal.confirm(
        CLILocalized.format("cli.macro.remove.confirm", macro.name, current.name),
        force: force
      )
      let updated = try current.replacing(macros: current.macros.filter { $0.id != macro.id })
        .validatedForCLI()
      let snapshot = try await ServiceConnection.withDeadline(seconds: timeout) {
        try await client.updateRemappingProfile(updated, expectedCurrent: current)
      }
      let result = Result(profile: try savedSummary(updated.id, in: snapshot), removed: macro.name)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIStatus(details: result))
      case .plain: CLIOutput.plain([[macro.name]])
      case .human:
        CLIOutput.success(CLILocalized.format("cli.macro.remove.done", macro.name, current.name))
      }
    }
  }
}
