import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ErrorCodeTests {
  private struct Catalog: Decodable {
    struct Entry: Decodable {
      let code: String
      let domain: String
      let name: String
      let status: String
      let wire: String?
    }
    let codes: [Entry]
  }

  private func repositoryResource(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Errors
      .deletingLastPathComponent()  // OpenJoystickDriverKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repository root
      .appendingPathComponent(path)
  }

  @Test
  func theActiveCatalogEntriesAreTheCases() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.json"))
    let active = try JSONDecoder().decode(Catalog.self, from: data).codes.filter {
      $0.status == "active"
    }
    #expect(active.map(\.code) == ErrorCode.allCases.map(\.rawValue))
    #expect(active.map(\.name) == ErrorCode.allCases.map { "\($0)" })
    #expect(active.map(\.domain) == ErrorCode.allCases.map(\.domain.rawValue))
  }

  @Test
  func eachRemappingCodeIsTheCatalogEntryOfItsWireValue() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.json"))
    let remapping = try JSONDecoder().decode(Catalog.self, from: data).codes.filter {
      $0.domain == "remapping" && $0.status == "active"
    }
    // One catalog entry per RPC code, in the declaration order of the enum.
    #expect(
      remapping.map(\.wire) == ApplicationServiceRemappingRPCError.Code.allCases.map(\.rawValue)
    )
    #expect(
      remapping.map(\.code)
        == ApplicationServiceRemappingRPCError.Code.allCases.map(\.errorCode.rawValue)
    )
  }

  @Test
  func everyCodeHasAnExplanationInTheTemplate() throws {
    let template = try String(
      contentsOf: repositoryResource(
        "Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings"
      ),
      encoding: .utf8
    )
    for code in ErrorCode.allCases {
      #expect(template.contains("\"error.\(code.rawValue)\" = "), "\(code.rawValue)")
    }
  }

  @Test
  func theExplanationIsLocalized() {
    for code in ErrorCode.allCases {
      #expect(code.localizedExplanation != "error.\(code.rawValue)")
    }
  }

  @Test
  func theRawValueIsTheWireValue() throws {
    let data = try JSONEncoder().encode([ErrorCode.tooSlow])
    #expect(String(bytes: data, encoding: .utf8) == "[\"E1007\"]")
  }
}
