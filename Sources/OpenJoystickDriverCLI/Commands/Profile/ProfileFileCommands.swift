import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Decodes and validates a profile document, turning any error into a usage error.
func decodeProfile(_ data: Data, source: String) throws -> RemappingProfile {
  do { return try RemappingProfileFileStore.load(from: data) } catch {
    throw CLIFailure.usage(
      CLILocalized.format(
        "cli.profile.document_invalid",
        "%@ is not a valid profile: %@",
        source,
        error.localizedDescription
      )
    )
  }
}

struct ProfileImportCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "import",
    abstract: CLILocalized.text(
      "cli.profile.import.abstract",
      "Add a profile from a file that 'ojd profile export' wrote."
    ),
    discussion: CLILocalized.text(
      "cli.profile.import.discussion",
      "Use - to read the profile from stdin. A profile with the same ID as an existing one "
        + "replaces it."
    )
  )

  /// The `--json` result. `replaced` is true when a profile with the same ID existed.
  struct Result: Encodable, Equatable {
    let profile: ProfileSummary
    let replaced: Bool
  }

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.import.file", "The profile file, or - for stdin."),
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
              "Replaced '%@' (%@).",
              imported.name,
              imported.id.uuidString
            )
            : CLILocalized.format(
              "cli.profile.import.added",
              "Imported '%@' (%@).",
              imported.name,
              imported.id.uuidString
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
      "cli.profile.export.abstract",
      "Print a profile as a file that 'ojd profile import' reads."
    ),
    discussion: CLILocalized.text(
      "cli.profile.export.discussion",
      "The profile is JSON, so --json and --plain do not change the output."
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Option(
    name: [.short, .long],
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.export.output",
        "Write the profile to this file instead of stdout."
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
          .failure,
          CLILocalized.format(
            "cli.profile.export.write_failed",
            "Cannot write %@: %@",
            output,
            error.localizedDescription
          )
        )
      }
      CLIOutput.success(
        CLILocalized.format("cli.profile.export.done", "Wrote '%@' to %@.", document.name, output)
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
        .failure,
        CLILocalized.format(
          "cli.profile.edit.editor_failed",
          "The editor exited with status %lld. Nothing changed.",
          Int(process.terminationStatus)
        )
      )
    }
  }
}

struct ProfileEditCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "edit",
    abstract: CLILocalized.text("cli.profile.edit.abstract", "Change a profile in your editor."),
    discussion: CLILocalized.text(
      "cli.profile.edit.discussion",
      "Opens the profile file in $VISUAL, $EDITOR, or vi, then validates and saves it. Needs a "
        + "terminal. Without one, export the profile, change the file, and import it."
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
            "cli.profile.edit.needs_terminal",
            "'ojd profile edit' needs a terminal. Use 'ojd profile export' and "
              + "'ojd profile import' instead."
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
          message: CLILocalized.text("cli.profile.edit.unchanged", "Nothing changed.")
        )
        return
      }
      let after = try await ServiceConnection.request {
        try await $0.updateRemappingProfile(edited, expectedCurrent: current)
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(edited.id, in: after), changed: true),
        message: CLILocalized.format("cli.profile.edit.done", "Saved '%@'.", edited.name)
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
          "cli.profile.edit.id_changed",
          "The edit changed the profile ID. Nothing changed; use 'ojd profile duplicate' to "
            + "make a copy."
        )
      )
    }
    return edited
  }
}
