import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Update checker") struct UpdateCheckerTests {
  @Test("stable channel selects the greatest stable SemVer tag") func stableChannelSelectsMaximum()
    async throws
  {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: "0.5.0-alpha.5")

    #expect(state == .upToDate("v0.4.1"))
  }

  @Test("prerelease channel selects the greatest SemVer tag") func prereleaseChannelSelectsMaximum()
    async throws
  {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: "0.5.0-alpha.5", includePrereleases: true)

    #expect(state == .upToDate("v0.5.0-alpha.4"))
  }

  @Test("available update uses a tag page without a release object")
  func availableUpdateUsesTagPage() async throws {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: "0.3.0")
    guard case .available(let info) = state else {
      Issue.record("Expected available update, got \(state)")
      return
    }

    #expect(info.tagName == "v0.4.1")
    #expect(info.htmlURL.absoluteString == "https://github.example/project/tree/v0.4.1")
  }

  @Test(
    "equal and installed-newer checks retain the selected remote tag",
    arguments: ["0.4.1", "0.5.0"]
  ) func noUpdateRetainsSelectedTag(currentVersion: String) async throws {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: currentVersion)

    #expect(state == .upToDate("v0.4.1"))
  }

  @Test("selection spans every linked tag page") func selectionSpansPagination() async throws {
    let checker = try Self.checker(path: "/paged-tags")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .available(let info) = state else {
      Issue.record("Expected available update, got \(state)")
      return
    }
    #expect(info.tagName == "v2.0.0")
  }

  @Test("pagination cycles fail") func paginationCyclesFail() async throws {
    let checker = try Self.checker(path: "/cycle-tags")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .failed(let message) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(message.contains("cycle"))
  }

  @Test("unsafe pagination links fail") func unsafePaginationLinksFail() async throws {
    let checker = try Self.checker(path: "/unsafe-tags")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .failed(let message) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(message.contains("unsafe"))
  }

  @Test("HTTP errors fail") func httpErrorsFail() async throws {
    let checker = try Self.checker(path: "/http-error")

    let state = await checker.check(currentVersion: "1.0.0")

    #expect(state == .failed("GitHub returned HTTP 503"))
  }

  @Test("non-HTTP responses fail") func nonHTTPResponsesFail() async throws {
    let checker = try Self.checker(path: "/non-http")

    let state = await checker.check(currentVersion: "1.0.0")

    #expect(state == .failed("GitHub returned a non-HTTP response"))
  }

  @Test("a channel without valid tags fails", arguments: [false, true])
  func channelWithoutValidTagsFails(includePrereleases: Bool) async throws {
    let checker = try Self.checker(path: "/invalid-tags")

    let state = await checker.check(currentVersion: "1.0.0", includePrereleases: includePrereleases)

    guard case .failed(let message) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(message.contains("SemVer GitHub tags"))
  }

  private static func checker(path: String) throws -> UpdateChecker {
    UpdateChecker(
      tagsURL: try #require(URL(string: "https://api.example\(path)?per_page=100")),
      repositoryURL: try #require(URL(string: "https://github.example/project")),
      session: session()
    )
  }

  private static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UpdateURLProtocolStub.self]
    return URLSession(configuration: configuration)
  }
}

private final class UpdateURLProtocolStub: URLProtocol, @unchecked Sendable {
  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    if url.path == "/non-http" {
      let response = URLResponse(
        url: url,
        mimeType: "application/json",
        expectedContentLength: 2,
        textEncodingName: nil
      )
      finish(response: response, json: "[]")
      return
    }

    let stub = Self.stub(for: url)
    guard
      let response = HTTPURLResponse(
        url: url,
        statusCode: stub.status,
        httpVersion: nil,
        headerFields: stub.headers
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    finish(response: response, json: stub.json)
  }

  override func stopLoading() {}

  private func finish(response: URLResponse, json: String) {
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(json.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  private static func stub(for url: URL) -> (status: Int, headers: [String: String], json: String) {
    switch (url.path, queryValue("page", in: url)) {
    case ("/mixed-tags", _): return (200, [:], tags("v0.4.0", "latest", "v0.5.0-alpha.4", "v0.4.1"))
    case ("/invalid-tags", _): return (200, [:], tags("latest", "v01.2.3"))
    case ("/paged-tags", nil):
      return (
        200, ["Link": "<https://api.example/paged-tags?page=2>; rel=\"next\""], tags("v1.5.0")
      )
    case ("/paged-tags", "2"): return (200, [:], tags("v0.1.0", "v2.0.0"))
    case ("/cycle-tags", nil):
      return (
        200, ["Link": "<https://api.example/cycle-tags?page=2>; rel=\"next\""], tags("v1.0.0")
      )
    case ("/cycle-tags", "2"):
      return (
        200, ["Link": "<https://api.example/cycle-tags?per_page=100>; rel=next"], tags("v1.1.0")
      )
    case ("/unsafe-tags", _):
      return (200, ["Link": "<https://attacker.example/tags?page=2>; rel=\"next\""], tags("v1.0.0"))
    case ("/http-error", _): return (503, [:], "{}")
    default: return (404, [:], "{}")
    }
  }

  private static func tags(_ names: String...) -> String {
    "[" + names.map { "{\"name\":\"\($0)\"}" }.joined(separator: ",") + "]"
  }

  private static func queryValue(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?
      .value
  }
}
