import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Update checker")
struct UpdateCheckerTests {
  @Test("stable channel selects the greatest stable SemVer tag")
  func stableChannelSelectsMaximum() async throws {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: "0.5.0-alpha.5")

    #expect(state == .aheadOfLatestRelease(current: "0.5.0-alpha.5", latest: "v0.4.1"))
  }

  @Test("prerelease channel selects the greatest SemVer tag")
  func prereleaseChannelSelectsMaximum() async throws {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: "0.5.0-alpha.5", includePrereleases: true)

    #expect(state == .aheadOfLatestRelease(current: "0.5.0-alpha.5", latest: "v0.5.0-alpha.4"))
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

  @Test("a tester build is offered to the prerelease channel and ordered after its release")
  func testerBuildIsOfferedAfterTheReleaseBeforeIt() async throws {
    let checker = try Self.checker(path: "/tester-tags")

    let offered = await checker.check(currentVersion: "0.6.0-alpha.2", includePrereleases: true)
    guard case .available(let info) = offered else {
      Issue.record("Expected available update, got \(offered)")
      return
    }
    #expect(info.tagName == "0.6.0-alpha.2.tester.2")

    let hidden = await checker.check(currentVersion: "0.6.0-alpha.2")
    #expect(hidden == .aheadOfLatestRelease(current: "0.6.0-alpha.2", latest: "0.5.0"))

    let newest = await checker.check(
      currentVersion: "0.6.0-alpha.2.tester.2+build.1.2.3.sha.0123456789ab",
      includePrereleases: true
    )
    #expect(
      newest
        == .upToDate(
          current: "0.6.0-alpha.2.tester.2+build.1.2.3.sha.0123456789ab",
          latest: "0.6.0-alpha.2.tester.2"
        )
    )
  }

  @Test("a tester build is offered the release it leads to, a stable one included")
  func testerBuildIsOfferedTheReleaseItLeadsTo() async throws {
    let checker = try Self.checker(path: "/tester-then-release")

    let prerelease = await checker.check(
      currentVersion: "0.6.0-alpha.2.tester.2",
      includePrereleases: true
    )
    guard case .available(let info) = prerelease else {
      Issue.record("Expected available update, got \(prerelease)")
      return
    }
    #expect(info.tagName == "0.6.0-alpha.3")

    let stable = await checker.check(currentVersion: "0.5.1-tester.1")
    guard case .available(let release) = stable else {
      Issue.record("Expected available update, got \(stable)")
      return
    }
    #expect(release.tagName == "0.5.1")
  }

  @Test("the running version equal to the latest tag is up to date")
  func equalVersionIsUpToDate() async throws {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: "0.4.1")

    #expect(state == .upToDate(current: "0.4.1", latest: "v0.4.1"))
  }

  @Test("a running version newer than the latest tag reports both versions")
  func newerVersionReportsBothVersions() async throws {
    let checker = try Self.checker(path: "/mixed-tags")

    let state = await checker.check(currentVersion: "0.5.0")

    #expect(state == .aheadOfLatestRelease(current: "0.5.0", latest: "v0.4.1"))
  }

  @Test("selection spans every linked tag page")
  func selectionSpansPagination() async throws {
    let checker = try Self.checker(path: "/paged-tags")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .available(let info) = state else {
      Issue.record("Expected available update, got \(state)")
      return
    }
    #expect(info.tagName == "v2.0.0")
  }

  @Test("pagination cycles fail")
  func paginationCyclesFail() async throws {
    let checker = try Self.checker(path: "/cycle-tags")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .failed(let failure) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(failure.reason == .paginationCycle)
  }

  @Test("unsafe pagination links fail")
  func unsafePaginationLinksFail() async throws {
    let checker = try Self.checker(path: "/unsafe-tags")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .failed(let failure) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(failure.reason == .unsafePaginationLink)
  }

  @Test("HTTP errors fail")
  func httpErrorsFail() async throws {
    let checker = try Self.checker(path: "/http-error")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .failed(let failure) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(failure.reason == .httpStatus(503))
  }

  @Test("non-HTTP responses fail")
  func nonHTTPResponsesFail() async throws {
    let checker = try Self.checker(path: "/non-http")

    let state = await checker.check(currentVersion: "1.0.0")

    guard case .failed(let failure) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(failure.reason == .invalidResponse)
  }

  @Test("a channel without valid tags fails", arguments: [false, true])
  func channelWithoutValidTagsFails(includePrereleases: Bool) async throws {
    let checker = try Self.checker(path: "/invalid-tags")

    let state = await checker.check(currentVersion: "1.0.0", includePrereleases: includePrereleases)

    guard case .failed(let failure) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(failure.reason == .noValidTags)
  }

  @Test("cancelling a check cancels the in-flight request", .timeLimit(.minutes(1)))
  func cancellingCheckCancelsInFlightRequest() async throws {
    var started = UpdateURLProtocolStub.stalledRequests.stream.makeAsyncIterator()
    // The description URLSession gives a request that its task cancels; a request that timed out
    // describes itself differently.
    let stalledURL = try #require(URL(string: "https://api.example/stalled"))
    let session = Self.session()
    let reference = Task { try await session.data(from: stalledURL) }
    _ = await started.next()
    reference.cancel()
    let cancelledDescription = failureDescription(of: await reference.result)

    let checker = try Self.checker(path: "/stalled")
    let check = Task { await checker.check(currentVersion: "1.0.0") }
    _ = await started.next()

    check.cancel()
    let state = await check.value

    guard case .failed(let failure) = state else {
      Issue.record("Expected failed state, got \(state)")
      return
    }
    #expect(failure.reason == .transport)
    #expect(failure.message == cancelledDescription)
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

private func failureDescription<Success>(of result: Result<Success, any Error>) -> String? {
  if case .failure(let error) = result { return error.localizedDescription }
  return nil
}

private final class UpdateURLProtocolStub: URLProtocol, @unchecked Sendable {
  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  /// Yields once each time a `/stalled` request starts loading; that request never finishes.
  static let stalledRequests = AsyncStream<Void>.makeStream()

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    if url.path == "/stalled" {
      Self.stalledRequests.continuation.yield()
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
    case ("/tester-tags", _):
      return (
        200, [:],
        tags("0.5.0", "0.6.0-alpha.2", "0.6.0-alpha.2.tester.1", "0.6.0-alpha.2.tester.2")
      )
    case ("/tester-then-release", _):
      return (
        200, [:],
        tags("0.5.0", "0.5.1", "0.6.0-alpha.2", "0.6.0-alpha.2.tester.2", "0.6.0-alpha.3")
      )
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
