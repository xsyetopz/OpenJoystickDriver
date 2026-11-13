import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ErrorCodeTests {
  private struct Catalog: Decodable {
    struct Entry: Decodable {
      let code: String
      let domain: String
      let name: String
      let wire: String?
      let exitCode: Int32?
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
  func activeCatalogEntriesAreCases() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.plist"))
    let active = try PropertyListDecoder().decode(Catalog.self, from: data).codes
    #expect(active.map(\.code) == ErrorCode.allCases.map(\.rawValue))
    #expect(active.map(\.name) == ErrorCode.allCases.map { "\($0)" })
    #expect(active.map(\.domain) == ErrorCode.allCases.map(\.domain.rawValue))
  }

  @Test
  func ojdFailsWithExitStatusesThatCommandLinePageDocuments() throws {
    #expect(ErrorCode.commandLineExitStatuses == [1, 64, 69, 77, 127])
    let page = try String(
      contentsOf: repositoryResource("wiki/Command-Line.md"),
      encoding: .utf8
    )
    for status in ErrorCode.commandLineExitStatuses {
      #expect(page.contains("| \(status) |"), "\(status)")
    }
  }

  @Test
  func catalogListsExitStatusOfEachCommandLineCodeAndNoOther() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.plist"))
    let entries = try PropertyListDecoder().decode(Catalog.self, from: data).codes
    for (entry, code) in zip(entries, ErrorCode.allCases) {
      #expect(
        entry.exitCode == (code.domain == .commandLine ? code.commandLineExitStatus : nil),
        "\(entry.code)"
      )
    }
  }

  @Test
  func everyCodeStartsWithPrefixOfItsDomain() {
    let prefixes = ErrorCode.Domain.allCases.map(\.codePrefix)
    #expect(Set(prefixes).count == prefixes.count)
    for code in ErrorCode.allCases {
      #expect(code.rawValue.hasPrefix(code.domain.codePrefix), "\(code.rawValue)")
    }
  }

  @Test
  func headerCodesAreEndpointCodes() {
    #expect(
      [ErrorCode.unsupportedEndpointVersion, .unexpectedKind, .missingHeader].allSatisfy {
        $0.domain == .endpoint
      }
    )
  }

  @Test
  func eachRemappingCodeIsCatalogEntryOfItsWireValue() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.plist"))
    let remapping = try PropertyListDecoder().decode(Catalog.self, from: data).codes.filter {
      $0.wire != nil
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
  func everyCodeHasExplanationInEnglishCatalog() throws {
    let english = try String(
      contentsOf: repositoryResource(
        "Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings"
      ),
      encoding: .utf8
    )
    for code in ErrorCode.allCases {
      #expect(english.contains("\"error.\(code.rawValue).message\" = "), "\(code.rawValue)")
    }
  }

  @Test
  func explanationIsLocalized() {
    for code in ErrorCode.allCases {
      #expect(code.localizedExplanation != "error.\(code.rawValue).message")
    }
  }

  @Test
  func rawValueIsWireValue() throws {
    let data = try JSONEncoder().encode([ErrorCode.tooSlow])
    #expect(String(bytes: data, encoding: .utf8) == "[\"E1006\"]")
  }
}
