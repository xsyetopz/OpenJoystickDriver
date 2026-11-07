import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The recorded Wii Remote reports in `Fixtures/Wii/`: one file per case, a header line that names
/// the source, then the report as uppercase hex pairs.
enum WiiFixtures {
  /// The file names without extension, sorted.
  static func names() throws -> [String] {
    let urls = try #require(
      Bundle.module.urls(forResourcesWithExtension: "hex", subdirectory: "Wii")
    )
    return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
  }

  /// The header line of fixture `name`.
  static func header(_ name: String) throws -> String {
    try lines(name).first { $0.hasPrefix("#") } ?? ""
  }

  /// The report bytes of fixture `name`.
  static func report(_ name: String) throws -> Data {
    let hex = try #require(try lines(name).first { !$0.hasPrefix("#") })
    return Data(try #require(HexBytes.parse(hex), "\(name) is uppercase hex pairs"))
  }

  /// The names of the fixtures whose report id is `id`.
  static func names(id: UInt8) throws -> [String] {
    try names().filter { UInt8($0.prefix(2), radix: 16) == id }
  }

  private static func lines(_ name: String) throws -> [String] {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: "hex", subdirectory: "Wii")
    )
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
  }
}
