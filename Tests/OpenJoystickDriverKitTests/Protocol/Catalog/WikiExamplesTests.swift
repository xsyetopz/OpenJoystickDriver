import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Each complete XML property list in the record and mod wiki pages loads as the kind it states.
struct WikiExamplesTests {
  private static let pages = ["wiki/Controller-Records.md", "wiki/Writing-Controller-Mods.md"]

  private static func repositoryResource(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Catalog
      .deletingLastPathComponent()  // Protocol
      .deletingLastPathComponent()  // OpenJoystickDriverKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repository root
      .appendingPathComponent(path)
  }

  /// The documents of the page: each fenced `xml` block that starts with the XML declaration.
  private static func documents(in page: String) throws -> [Data] {
    let text = try String(contentsOf: repositoryResource(page), encoding: .utf8)
    return text.components(separatedBy: "```xml\n").dropFirst().compactMap { block in
      let body = block.components(separatedBy: "```")[0]
      return body.hasPrefix("<?xml") ? Data(body.utf8) : nil
    }
  }

  private static func kind(of data: Data) throws -> String {
    try #require(OrderedJSON(document: data, file: "wiki")["kind"]?.string)
  }

  @Test(arguments: pages)
  func everyCompleteExampleLoadsAsItsKind(page: String) throws {
    let examples = try Self.documents(in: page)
    #expect(!examples.isEmpty, "\(page) holds no complete example")
    for data in examples {
      switch try Self.kind(of: data) {
      case ControllerRecordDocument.kind, ControllerPatch.kind:
        _ = try ControllerRecordSet.validate(data)
      case "VirtualDevice":
        _ = try VirtualHIDProfileOverrideStore.parse(data)
      case "ModPackage":
        _ = try ModPackageManifest.parse(data)
      case let other:
        Issue.record("\(page) holds an example of kind \(other) that no reader is named for")
      }
    }
  }
}
