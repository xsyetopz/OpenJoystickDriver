import Foundation

public struct UpdateInfo: Equatable, Sendable {
  public let tagName: String
  public let version: SemanticVersion
  public let htmlURL: URL

  public init(tagName: String, version: SemanticVersion, htmlURL: URL) {
    self.tagName = tagName
    self.version = version
    self.htmlURL = htmlURL
  }
}

public enum UpdateCheckState: Equatable, Sendable {
  case idle
  case checking
  case upToDate(String)
  case available(UpdateInfo)
  case failed(String)
}

public struct UpdateChecker: Sendable {
  public static let requestTimeoutSeconds: TimeInterval = 15

  public static var defaultLatestReleaseURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.path = "/repos/xsyetopz/OpenJoystickDriver/releases/latest"
    return components.url ?? URL(fileURLWithPath: "/")
  }

  public static var defaultReleasesURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.path = "/repos/xsyetopz/OpenJoystickDriver/releases"
    return components.url ?? URL(fileURLWithPath: "/")
  }

  private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case htmlURL = "html_url"
      case draft
      case prerelease
    }
  }

  public let latestReleaseURL: URL
  public let releasesURL: URL
  public let session: URLSession

  public init(
    latestReleaseURL: URL = Self.defaultLatestReleaseURL,
    releasesURL: URL = Self.defaultReleasesURL,
    session: URLSession = .shared
  ) {
    self.latestReleaseURL = latestReleaseURL
    self.releasesURL = releasesURL
    self.session = session
  }

  public func check(
    currentVersion rawCurrentVersion: String,
    includePrereleases: Bool = false
  ) async -> UpdateCheckState {
    guard let currentVersion = SemanticVersion(rawCurrentVersion) else {
      return .failed("Current app version is not SemVer: \(rawCurrentVersion)")
    }

    do {
      let release = try await latestRelease(includePrereleases: includePrereleases)
      guard let latestVersion = SemanticVersion(release.tagName) else {
        return .failed("Latest GitHub release tag is not SemVer: \(release.tagName)")
      }

      let info = UpdateInfo(
        tagName: release.tagName,
        version: latestVersion,
        htmlURL: release.htmlURL
      )
      return latestVersion > currentVersion ? .available(info) : .upToDate(rawCurrentVersion)
    } catch let error as UpdateCheckerError {
      return .failed(error.message)
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  private func latestRelease(includePrereleases: Bool) async throws -> GitHubRelease {
    if includePrereleases {
      return try await latestReleaseIncludingPrereleases()
    }

    let release: GitHubRelease = try await decode(url: latestReleaseURL)
    guard !release.draft else { throw UpdateCheckerError("Latest GitHub release is a draft") }
    guard !release.prerelease else {
      throw UpdateCheckerError("Latest GitHub release is a prerelease")
    }
    return release
  }

  private func latestReleaseIncludingPrereleases() async throws -> GitHubRelease {
    let releases: [GitHubRelease] = try await decode(url: releasesURL)
    let candidates = releases.compactMap { release -> (GitHubRelease, SemanticVersion)? in
      guard !release.draft, let version = SemanticVersion(release.tagName) else { return nil }
      return (release, version)
    }
    guard let latest = candidates.max(by: { $0.1 < $1.1 }) else {
      throw UpdateCheckerError("No non-draft SemVer GitHub releases found")
    }
    return latest.0
  }

  private func decode<T: Decodable>(url: URL) async throws -> T {
    var request = URLRequest(url: url)
    request.timeoutInterval = Self.requestTimeoutSeconds
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("OpenJoystickDriver", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await data(for: request)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw UpdateCheckerError("GitHub returned HTTP \(http.statusCode)")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let task = session.dataTask(with: request) { data, response, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let data, let response else {
          continuation.resume(throwing: URLError(.badServerResponse))
          return
        }
        continuation.resume(returning: (data, response))
      }
      task.resume()
    }
  }
}

private struct UpdateCheckerError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}
