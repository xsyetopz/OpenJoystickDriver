import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Update checker")
struct UpdateCheckerTests {
  @Test("stable checks use latest release endpoint")
  func stableChecksUseLatestReleaseEndpoint() async {
    let checker = UpdateChecker(
      latestReleaseURL: URL(string: "https://example.test/stable-latest")!,
      releasesURL: URL(string: "https://example.test/prerelease-releases")!,
      session: Self.session()
    )

    let state = await checker.check(
      currentVersion: "0.5.0",
      includePrereleases: false
    )
    #expect(state == .upToDate("0.5.0"))
  }

  @Test("prerelease checks include newer prereleases")
  func prereleaseChecksIncludeNewerPrereleases() async {
    let checker = UpdateChecker(
      releasesURL: URL(string: "https://example.test/prerelease-releases")!,
      session: Self.session()
    )

    let state = await checker.check(currentVersion: "0.5.0", includePrereleases: true)
    guard case .available(let info) = state else {
      Issue.record("Expected available update, got \(state)")
      return
    }
    #expect(info.tagName == "v0.6.0-beta.1")
  }

  @Test("prerelease checks ignore drafts and invalid tags")
  func prereleaseChecksIgnoreDraftsAndInvalidTags() async {
    let checker = UpdateChecker(
      releasesURL: URL(string: "https://example.test/drafts-releases")!,
      session: Self.session()
    )

    let state = await checker.check(currentVersion: "0.5.0", includePrereleases: true)
    guard case .available(let info) = state else {
      Issue.record("Expected available update, got \(state)")
      return
    }
    #expect(info.tagName == "v0.5.1")
  }

  private static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
  }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url,
          let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          ) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.data(for: url))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func data(for url: URL) -> Data {
    let json: String
    switch url.path {
    case "/stable-latest":
      json = """
        {"tag_name":"v0.5.0","html_url":"https://example.test/stable","draft":false,"prerelease":false}
        """
    case "/prerelease-releases":
      json = """
        [
          {"tag_name":"v0.6.0-beta.1","html_url":"https://example.test/beta","draft":false,"prerelease":true},
          {"tag_name":"v0.5.0","html_url":"https://example.test/stable","draft":false,"prerelease":false}
        ]
        """
    case "/drafts-releases":
      json = """
        [
          {"tag_name":"v9.0.0","html_url":"https://example.test/draft","draft":true,"prerelease":false},
          {"tag_name":"latest","html_url":"https://example.test/invalid","draft":false,"prerelease":false},
          {"tag_name":"v0.5.1","html_url":"https://example.test/stable","draft":false,"prerelease":false}
        ]
        """
    default:
      json = "{}"
    }
    return Data(json.utf8)
  }
}
