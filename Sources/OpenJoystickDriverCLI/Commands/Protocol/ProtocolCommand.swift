import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd protocol` command group: validate, install and list protocol descriptions.
struct ProtocolCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "protocol",
    abstract: CLILocalized.text("cli.protocol.group.abstract"),
    discussion: CLILocalized.text("cli.protocol.group.discussion"),
    subcommands: [
      ProtocolValidateCommand.self, ProtocolInstallCommand.self, ProtocolListCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// Where `ojd protocol` reads and writes the user's protocol descriptions.
enum ProtocolStore {
  /// The user's `Controllers` folder, which locates the `Protocols` and `Packages` folders beside
  /// it; tests replace it.
  @TaskLocal
  static var controllers = ControllerRecordSet.userDirectory

  /// The user's `Protocols` folder.
  static var directory: URL { DocumentedProtocolFamilies.directory(besides: controllers) }

  /// The documented family in the file named by the `FILE` operand.
  ///
  /// - Throws: ``CLIFailure`` with the E5xxx code of the refusal.
  static func read(_ path: String) throws -> DocumentedProtocolFamily {
    do { return try DocumentedProtocolFamilies.read(URL(fileURLWithPath: path)) } catch {
      if CLIContext.current.format == .json { try CLIOutput.json(ProtocolValidation(error)) }
      throw CLIFailure(
        error.code,
        CLILocalized.format("cli.mod.group.refused", path, error.detail)
      )
    }
  }
}

/// The `--json` result of `protocol validate`.
struct ProtocolValidation: Encodable, Equatable {
  /// Whether the description is accepted.
  let valid: Bool
  /// Why the description is refused.
  let problem: String?
  /// The E5xxx code of the refusal.
  let code: String?
  /// The family name.
  let name: String?
  /// The display name that the document gives.
  let displayName: String?

  /// Describes an accepted description.
  init(_ family: DocumentedProtocolFamily) {
    valid = true
    problem = nil
    code = nil
    name = family.name
    displayName = family.displayName
  }

  /// Describes the refusal `error`.
  init(_ error: ProtocolDescriptionProblem) {
    valid = false
    problem = error.detail
    code = error.code.rawValue
    name = nil
    displayName = nil
  }
}

/// One family in `protocol list --json`.
struct ProtocolEntry: Encodable, Equatable {
  /// Where a family comes from.
  enum Source: String, Encodable {
    /// OJD builds the family in.
    case builtIn = "BuiltIn"
    /// A description in the user's `Protocols` folder.
    case user = "User"
    /// A description in a mod package.
    case package = "Package"
  }

  /// The family name.
  let name: String
  /// The name as a person reads it.
  let displayName: String
  /// Where the family comes from.
  let source: Source
  /// The mod package that holds the description, for a package family.
  let package: String?
  /// The description file, for a documented family.
  let file: String?

  /// Describes the built-in family `family`.
  init(builtIn family: PhysicalProtocolID) {
    name = family.rawValue
    displayName = family.displayName
    source = .builtIn
    package = nil
    file = nil
  }

  /// Describes the documented family `family`.
  init(_ family: DocumentedProtocolFamily) {
    name = family.name
    displayName = family.displayName
    source = family.package == nil ? .user : .package
    package = family.package
    file = family.file.path
  }

  /// Where the family comes from, in words.
  var sourceText: String {
    switch source {
    case .builtIn: CLILocalized.text("cli.protocol.list.builtIn")
    case .user: CLILocalized.text("cli.protocol.list.user")
    case .package: CLILocalized.format("cli.protocol.list.package", package ?? "")
    }
  }
}
