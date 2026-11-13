import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct AccessGrantStoreErrorTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let error: AccessGrantStoreError
    let code: ErrorCode
    /// The value that the message names after the text; nil for a message without one.
    let detail: String?

    var testDescription: String { code.rawValue }
  }

  private static let versionProblem = OpenJoystickDriverAPI.headerProblem(
    apiVersion: "x",
    kind: "AccessGrants",
    expected: "AccessGrants"
  )!
  private static let kindProblem = OpenJoystickDriverAPI.headerProblem(
    apiVersion: OpenJoystickDriverAPI.version,
    kind: "X",
    expected: "AccessGrants"
  )!

  static let cases: [Case] = [
    Case(
      error: .unsupported(versionProblem),
      code: .unsupportedAPIVersion,
      detail: versionProblem.message
    ),
    Case(error: .unsupported(kindProblem), code: .damagedAccessGrants, detail: kindProblem.message),
    Case(error: .unknownClient("a1b2c3d4"), code: .unknownAccessClient, detail: "a1b2c3d4"),
    Case(error: .notGrantable(.adHoc), code: .ungrantableClient, detail: "ad-hoc"),
    Case(error: .noScope, code: .noAccessScope, detail: nil),
    Case(error: .serviceStopped, code: .serviceStopping, detail: nil),
    Case(error: .duplicateToken("overlay"), code: .duplicateTokenName, detail: "overlay"),
    Case(error: .invalidTokenName("a b"), code: .invalidTokenName, detail: "a b"),
    Case(error: .invalidOrigin("ftp://x"), code: .invalidWebOrigin, detail: "ftp://x"),
    Case(error: .portUnavailable(80), code: .webPortUnavailable, detail: "80"),
    Case(error: .originsWithControl, code: .controlScopeWithOrigins, detail: nil),
  ]

  @Test(arguments: cases)
  func messageLeadsWithCodeAndItsLocalizedText(_ item: Case) {
    let message = item.error.errorDescription ?? ""
    let text = item.code.localizedExplanation
    #expect(item.error.code == item.code)
    #expect(!text.isEmpty && !text.hasPrefix("error."))
    #expect(message == "\(item.code.rawValue): \(text)" + (item.detail.map { " (\($0))" } ?? ""))
  }

  @Test
  func everyErrorCaseHasItsOwnCode() {
    let codes = Self.cases.map(\.code)
    #expect(Set(codes).count == codes.count)
  }
}
