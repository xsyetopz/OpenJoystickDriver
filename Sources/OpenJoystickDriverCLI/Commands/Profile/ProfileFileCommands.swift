import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Decodes and validates a profile document, turning any error into a failure with the code of
/// ``RemappingProfileFileStore/problemCode(_:)``.
///
/// - Parameters:
///   - data: The profile document.
///   - source: The file name that the failure names.
/// - Returns: The decoded profile.
/// - Throws: ``CLIFailure`` when the document is not a valid profile.
func decodeProfile(_ data: Data, source: String) throws -> RemappingProfile {
  do { return try RemappingProfileFileStore.load(from: data) } catch {
    throw CLIFailure(
      RemappingProfileFileStore.problemCode(error),
      CLILocalized.format(
        "cli.profile.group.documentInvalid",
        source,
        DocumentProblem.describe(error)
      )
    )
  }
}

/// The `ojd profile import` command: adds a profile from a file that `profile export` wrote.
///
/// A profile with the same ID as an installed profile replaces it.
struct ProfileImportCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "import",
    abstract: CLILocalized.text(
      "cli.profile.import.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.import.discussion"
    )
  )

  /// The `--json` result. `replaced` is true when a profile with the same ID existed.
  struct Result: Encodable, Equatable {
    /// The imported profile.
    let profile: ProfileSummary
    /// Whether the import replaced a profile.
    let replaced: Bool
  }

  /// The file to read, or `-` for standard input.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.import.file"),
      valueName: "file"
    )
  )
  var file: String

  /// `--app`: the bundle ID of an app that the imported profile applies to, repeated for more
  /// apps; without it the profile keeps the scope of the file.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.import.app"),
      valueName: "app-id"
    )
  )
  var app: [String] = []

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let source = file == "-" ? "stdin" : file
      let decoded = try decodeProfile(try RecordStore.read(file), source: source)
      let imported = try
        (app.isEmpty ? decoded : decoded.withApplicationScope(.application(appIDs: app)))
        .checkingPointerSpeedDriver()
      let (before, after) = try await ServiceConnection.request { client in
        let before = try await client.getRemappingSnapshot()
        return (before, try await client.importRemappingProfile(imported))
      }
      let result = Result(
        profile: try savedSummary(imported.id, in: after),
        replaced: before.profiles.contains { $0.id == imported.id }
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain([result.profile.row])
      case .human:
        CLIOutput.success(
          result.replaced
            ? CLILocalized.format(
              "cli.profile.import.replaced",
              imported.name,
              imported.id.uuidString
            )
            : CLILocalized.format(
              "cli.profile.import.added",
              imported.name,
              imported.id.uuidString
            )
        )
      }
    }
  }
}

/// The `ojd profile validate` command: checks a profile file without importing it.
///
/// It needs no running service.
struct ProfileValidateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: CLILocalized.text(
      "cli.profile.validate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.validate.discussion"
    )
  )

  /// The `--json` result.
  ///
  /// An invalid profile has only `valid` and `problem`.
  struct Result: Encodable, Equatable {
    /// Whether the profile is valid.
    let valid: Bool
    /// Why the profile is not valid.
    let problem: String?
    /// The profile ID.
    let id: String?
    /// The profile name.
    let name: String?
    /// The controller model of the profile.
    let controller: String?
    /// The app scope of the profile.
    let scope: String?

    /// Describes a valid `profile`.
    init(_ profile: RemappingProfile) {
      valid = true
      problem = nil
      id = profile.id.uuidString
      name = profile.name
      controller = deviceIdentity(
        vendorID: Int(profile.device.vendorID),
        productID: Int(profile.device.productID)
      )
      scope = ProfileText.scope(profile.applicationScope)
    }

    /// Describes an invalid profile by its `problem`.
    init(problem: String) {
      valid = false
      self.problem = problem
      id = nil
      name = nil
      controller = nil
      scope = nil
    }
  }

  /// The file to read, or `-` for standard input.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.validate.file"),
      valueName: "FILE|-"
    )
  )
  var file: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let data = try RecordStore.read(file)
      let profile: RemappingProfile
      do { profile = try RemappingProfileFileStore.load(from: data) } catch {
        let problem = DocumentProblem.describe(error)
        if CLIContext.current.format == .json { try CLIOutput.json(Result(problem: problem)) }
        throw CLIFailure(
          RemappingProfileFileStore.problemCode(error),
          CLILocalized.format(
            "cli.profile.group.documentInvalid",
            file == "-" ? "stdin" : file,
            problem
          )
        )
      }
      let result = Result(profile)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [result.id ?? "", result.name ?? "", result.controller ?? "", result.scope ?? ""]
        ])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.profile.validate.valid",
            file == "-" ? "stdin" : file,
            profile.name,
            result.controller ?? "",
            result.scope ?? ""
          )
        )
      }
    }
  }
}

/// The `ojd profile export` command: prints a profile file to standard output, or writes it to
/// `--output`.
struct ProfileExportCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: CLILocalized.text(
      "cli.profile.export.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.export.discussion"
    )
  )

  /// The profile to export.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// `--output`: the file to write instead of standard output.
  @Option(
    name: [.short, .long],
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.export.output"
      ),
      valueName: "file"
    )
  )
  var output: String?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = profile
      let (document, _) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      guard let output else {
        CLIOutput.raw(try RemappingProfileFileStore.encodedPlist(document))
        return
      }
      do { try RemappingProfileFileStore.write(document, to: URL(fileURLWithPath: output)) } catch {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.profile.export.writeFailed",
            output,
            error.localizedDescription
          )
        )
      }
      CLIOutput.success(
        CLILocalized.format("cli.profile.export.done", document.name, output)
      )
    }
  }
}

/// Runs the user's editor on a file; tests replace it.
enum ProfileEditor {
  /// Opens the file in the editor.
  @TaskLocal
  static var open: @Sendable (URL) throws -> Void = { try run(on: $0) }

  /// `$VISUAL`, then `$EDITOR`, then `vi`, run through the shell like `git` does.
  static func command(environment: [String: String] = ProcessInfo.processInfo.environment) -> String
  {
    for key in ["VISUAL", "EDITOR"] {
      if let value = environment[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
        return value
      }
    }
    return "vi"
  }

  /// Runs the editor command on the file at `url` and waits for it.
  ///
  /// - Throws: ``CLIFailure`` when the editor cannot be started or does not succeed.
  private static func run(on url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // The path is a separate argument, so the shell never parses it.
    process.arguments = ["-c", command() + " \"$1\"", "sh", url.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CLIFailure(
        .aborted,
        CLILocalized.format(
          "cli.profile.edit.editorFailed",
          Int(process.terminationStatus)
        )
      )
    }
  }
}

/// The `ojd profile edit` command: opens a profile file in the editor, then checks and saves it.
///
/// It needs a terminal.
struct ProfileEditCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "edit",
    abstract: CLILocalized.text("cli.profile.edit.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.edit.discussion"
    )
  )

  /// The profile to edit.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      guard CLITerminal.canPrompt() else {
        throw CLIFailure.usage(
          CLILocalized.text(
            "cli.profile.edit.needsTerminal"
          )
        )
      }
      let selector = profile
      let (current, snapshot) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      let edited = try Self.edit(current)
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
        message: CLILocalized.format("cli.profile.edit.done", edited.name)
      )
    }
  }

  /// Opens `profile` in the editor and returns the valid profile the user saved.
  ///
  /// - Throws: ``CLIFailure`` when the saved file is not a valid profile or leaves the profile
  ///   unchanged.
  static func edit(_ profile: RemappingProfile) throws -> RemappingProfile {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-profile-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("profile.json")
    try RemappingProfileFileStore.write(profile, to: url)
    try ProfileEditor.open(url)
    let edited = try decodeProfile(try Data(contentsOf: url), source: url.lastPathComponent)
    guard edited.id == profile.id else {
      throw CLIFailure.usage(
        CLILocalized.text(
          "cli.profile.edit.idChanged"
        )
      )
    }
    return edited
  }
}
