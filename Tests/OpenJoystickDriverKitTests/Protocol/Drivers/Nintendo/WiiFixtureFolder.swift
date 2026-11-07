import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A subfolder of `Fixtures/Wii/` that holds fixtures which are not input reports: extension ids
/// and data, IR blocks and output sequences.
///
/// A file has a header line that names the source, then one line of uppercase hex pairs for each
/// byte string. A line that starts with `#` after the header is a step label.
struct WiiFixtureFolder {
  static let extensions = WiiFixtureFolder(name: "Extensions")
  static let ir = WiiFixtureFolder(name: "IR")
  static let sequences = WiiFixtureFolder(name: "Sequences")

  let name: String

  /// The file names without extension, sorted.
  func names() throws -> [String] {
    let urls = try #require(
      Bundle.module.urls(forResourcesWithExtension: "hex", subdirectory: "Wii/\(name)")
    )
    return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
  }

  /// The header line of fixture `fixture`.
  func header(_ fixture: String) throws -> String {
    try lines(fixture).first { $0.hasPrefix("#") } ?? ""
  }

  /// The byte strings of fixture `fixture`, in file order.
  func byteStrings(_ fixture: String) throws -> [Data] {
    try lines(fixture).filter { !$0.hasPrefix("#") }.map {
      Data(try #require(HexBytes.parse($0), "\(fixture) is uppercase hex pairs"))
    }
  }

  /// The only byte string of fixture `fixture`.
  func bytes(_ fixture: String) throws -> Data {
    let strings = try byteStrings(fixture)
    try #require(strings.count == 1, "\(fixture) holds one byte string")
    return strings[0]
  }

  private func lines(_ fixture: String) throws -> [String] {
    let url = try #require(
      Bundle.module.url(
        forResource: fixture,
        withExtension: "hex",
        subdirectory: "Wii/\(name)"
      )
    )
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
  }
}
