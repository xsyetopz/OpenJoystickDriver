import Foundation
import OpenJoystickDriverUSB
import SwifterKit

private struct Arguments {
  let output: URL
  let shortVersion: String
  let buildVersion: String

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

private enum ArgumentError: Error, CustomStringConvertible {
  case missingValue(String)
  case unknownOption(String)
  case usage

  var description: String {
    switch self {
    case .missingValue(let option): "missing value for \(option)"
    case .unknownOption(let option): "unknown option: \(option)"
    case .usage: "required arguments: --output PATH --short-version VERSION --build-version VERSION"
    }
  }
}

do {
  let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
  try DriverExtensionGenerator.generate(
    configuration: USBDriverKitExtensionConfiguration.driver,
    options: DriverExtensionGenerationOptions(
      shortVersion: arguments.shortVersion,
      buildVersion: arguments.buildVersion,
      deploymentTarget: "19.0"
    ),
    at: arguments.output
  )
} catch {
  FileHandle.standardError.write(Data("DriverKit generation failed: \(error)\n".utf8))
  exit(2)
}
