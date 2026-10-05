import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Decodes and validates a profile document, turning any error into a usage error.
func decodeProfile(_ data: Data, source: String) throws -> RemappingProfile {
  do { return try RemappingProfileFileStore.load(from: data) } catch {
    throw CLIFailure.usage(
      CLILocalized.format(
        "cli.profile.document_invalid",
        source,
        DocumentProblem.describe(error)
      )
    )
  }
}

struct ProfileImportCommand: AsyncParsableCommand {
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
    let profile: ProfileSummary
    let replaced: Bool
  }

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.import.file"),
      valueName: "file"
    )
  )
  var file: String

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let source = file == "-" ? "stdin" : file
      let imported = try decodeProfile(try RecordStore.read(file), source: source)
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

struct ProfileValidateCommand: AsyncParsableCommand {
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
  /// An invalid profile has only `valid` and `problem`.
  struct Result: Encodable, Equatable {
    let valid: Bool
    let problem: String?
    let id: String?
    let name: String?
    let controller: String?
    let scope: String?

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

    init(problem: String) {
      valid = false
      self.problem = problem
      id = nil
      name = nil
      controller = nil
      scope = nil
    }
  }

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.validate.file"),
      valueName: "FILE|-"
    )
  )
  var file: String

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let data = try RecordStore.read(file)
      let profile: RemappingProfile
      do { profile = try RemappingProfileFileStore.load(from: data) } catch {
        let problem = DocumentProblem.describe(error)
        if CLIContext.current.format == .json { try CLIOutput.json(Result(problem: problem)) }
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format(
            "cli.profile.document_invalid",
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

struct ProfileExportCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: CLILocalized.text(
      "cli.profile.export.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.export.discussion"
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

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

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = profile
      let (document, _) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      guard let output else {
        CLIOutput.stdout(try RemappingProfileFileStore.encodedJSON(document))
        return
      }
      do { try RemappingProfileFileStore.write(document, to: URL(fileURLWithPath: output)) } catch {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.profile.export.write_failed",
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
          "cli.profile.edit.editor_failed",
          Int(process.terminationStatus)
        )
      )
    }
  }
}

struct ProfileEditCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "edit",
    abstract: CLILocalized.text("cli.profile.edit.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.edit.discussion"
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      guard CLITerminal.canPrompt() else {
        throw CLIFailure.usage(
          CLILocalized.text(
            "cli.profile.edit.needs_terminal"
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
  static func edit(_ profile: RemappingProfile) throws -> RemappingProfile {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
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
          "cli.profile.edit.id_changed"
        )
      )
    }
    return edited
  }
}
