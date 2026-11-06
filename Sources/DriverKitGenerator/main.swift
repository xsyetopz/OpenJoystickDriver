import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB
import SwifterKit

/// The command-line options of `DriverKitGenerator`: the folder to write and the versions to stamp.
private struct Arguments {
  /// The folder that receives the generated DriverKit project; it must not exist yet.
  let output: URL
  /// The marketing version (`CFBundleShortVersionString`) written into the generated project.
  let shortVersion: String
  /// The build version (`CFBundleVersion`) written into the generated project.
  let buildVersion: String

  /// Reads `--output`, `--short-version` and `--build-version` from `values`.
  ///
  /// - Parameter values: The command-line arguments after the executable name, as option and value
  ///   pairs.
  /// - Throws: ``ArgumentError`` when an option has no value, an option is unknown, or one of
  ///   the three options is missing.
  init(_ values: [String]) throws {
    var output: String?
    var shortVersion: String?
    var buildVersion: String?
    var index = 0
    while index < values.count {
      let option = values[index]
      guard index + 1 < values.count else { throw ArgumentError.missingValue(option) }
      let value = values[index + 1]
      switch option {
      case "--output": output = value
      case "--short-version": shortVersion = value
      case "--build-version": buildVersion = value
      default: throw ArgumentError.unknownOption(option)
      }
      index += 2
    }
    guard let output, let shortVersion, let buildVersion else { throw ArgumentError.usage }
    self.output = URL(fileURLWithPath: output, isDirectory: true)
    self.shortVersion = shortVersion
    self.buildVersion = buildVersion
  }
}

/// The ways that the command-line arguments of `DriverKitGenerator` are refused.
private enum ArgumentError: Error, CustomStringConvertible {
  /// An option is the last argument and has no value; carries the option.
  case missingValue(String)
  /// The argument is not one of the three options; carries the argument.
  case unknownOption(String)
  /// One of `--output`, `--short-version` or `--build-version` is missing.
  case usage

  /// The message that the generator prints on standard error for the refused argument.
  var description: String {
    switch self {
    case .missingValue(let option): "missing value for \(option)"
    case .unknownOption(let option): "unknown option: \(option)"
    case .usage: "required arguments: --output PATH --short-version VERSION --build-version VERSION"
    }
  }
}

/// Thrown when a bundled controller record asks for the extension but its model is outside Apple's
/// `transport.usb` grant.
private struct OutsideGrantError: Error, CustomStringConvertible {
  /// The models that are extension-owned and outside the grant.
  let models: [ControllerModelID]

  /// The message that lists the offending models.
  var description: String {
    "ExtensionOwned records outside Apple's grant: "
      + models.map(\.description).joined(separator: ", ")
  }
}

do {
  let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
  let outsideGrant = USBDriverKitExtensionConfiguration.modelsOutsideGrant(
    extensionOwned: USBDriverKitExtensionConfiguration.extensionOwnedModels(
      in: ControllerRecordSet.bundled
    )
  )
  guard outsideGrant.isEmpty else { throw OutsideGrantError(models: outsideGrant) }
  try DriverExtensionGenerator.generate(
    configuration: USBDriverKitExtensionConfiguration.driver,
    options: DriverExtensionGenerationOptions(
      shortVersion: arguments.shortVersion,
      buildVersion: arguments.buildVersion,
      deploymentTarget: "21.0"
    ),
    at: arguments.output
  )
} catch DriverExtensionGenerationError.destinationExists(let path) {
  // Generation writes a complete project into a missing folder only, so an existing project is
  // never mixed with or overwritten by the generated one.
  FileHandle.standardError.write(
    Data(
      """
      DriverKit generation refused: \(path) already exists.
      Delete the folder or pass a path that does not exist.

      """.utf8
    )
  )
  exit(2)
} catch {
  FileHandle.standardError.write(Data("DriverKit generation failed: \(error)\n".utf8))
  exit(2)
}
