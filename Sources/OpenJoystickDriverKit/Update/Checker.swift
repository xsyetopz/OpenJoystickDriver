public import Foundation

/// A release that is newer than the running version.
public struct UpdateInfo: Equatable, Sendable {
  /// The Git tag of the release.
  public let tagName: String
  /// The version that the tag names.
  public let version: SemanticVersion
  /// The GitHub page of the tag.
  public let htmlURL: URL

  /// Creates the description of a release.
  public init(tagName: String, version: SemanticVersion, htmlURL: URL) {
    self.tagName = tagName
    self.version = version
    self.htmlURL = htmlURL
  }
}

/// Why an update check failed.
public enum UpdateCheckFailureReason: Equatable, Sendable {
  /// The running version is not a SemVer version.
  case invalidCurrentVersion
  /// No tag is a SemVer version.
  case noValidTags
  /// The tag pages link to a page that was already read.
  case paginationCycle
  /// The link to the next page leaves the scheme, host or port of the tags URL.
  case unsafePaginationLink
  /// The response is not HTTP, or does not decode as tags.
  case invalidResponse
  /// GitHub answered with this HTTP status.
  case httpStatus(Int)
  /// The request failed before a response arrived.
  case transport
}

/// The failure of an update check.
public struct UpdateCheckFailure: Equatable, Sendable {
  /// Why the check failed.
  public let reason: UpdateCheckFailureReason
  /// A description of the failure.
  public let message: String

  /// Creates a failure from its reason and message.
  public init(reason: UpdateCheckFailureReason, message: String) {
    self.reason = reason
    self.message = message
  }
}

/// The state of an update check.
public enum UpdateCheckState: Equatable, Sendable {
  /// No check has run.
  case idle
  /// A check is running.
  case checking
  /// The running version equals the latest release.
  case upToDate(current: String, latest: String)
  /// A newer release exists.
  case available(UpdateInfo)
  /// The running version is newer than the latest release.
  case aheadOfLatestRelease(current: String, latest: String)
  /// Only prereleases are published, and the check leaves them out.
  case onlyPrereleases
  /// The check failed.
  case failed(UpdateCheckFailure)
}

/// Looks for the latest release among the GitHub tags of the OJD repository.
public struct UpdateChecker: Sendable {
  /// The timeout of one request, in seconds.
  public static let requestTimeoutSeconds: TimeInterval = 15
  /// The HTTP status codes of a successful response.
  private static let httpSuccessStatusRange = 200...299

  /// The URL of the first page of the repository's tags, 100 to a page.
  public static var defaultTagsURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.path = "/repos/xsyetopz/OpenJoystickDriver/tags"
    components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
    return components.url ?? URL(fileURLWithPath: "/")
  }

  /// The URL of the repository on GitHub.
  public static var defaultRepositoryURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/xsyetopz/OpenJoystickDriver"
    return components.url ?? URL(fileURLWithPath: "/")
  }

  /// A tag in the GitHub tags response.
  private struct GitHubTag: Decodable {
    /// The name of the tag.
    let name: String
  }

  /// A tag with the version it names.
  private struct Candidate {
    /// The tag.
    let tag: GitHubTag
    /// The version that the tag names.
    let version: SemanticVersion
  }

  /// The URL of the first page of tags.
  public let tagsURL: URL
  /// The URL of the repository, which the tag pages are built on.
  public let repositoryURL: URL
  /// The session that sends the requests.
  public let session: URLSession

  /// Creates a checker for the tags at `tagsURL` of the repository at `repositoryURL`.
  public init(
    tagsURL: URL = Self.defaultTagsURL,
    repositoryURL: URL = Self.defaultRepositoryURL,
    session: URLSession = .shared
  ) {
    self.tagsURL = tagsURL
    self.repositoryURL = repositoryURL
    self.session = session
  }

  /// Compares `rawCurrentVersion` with the latest tag.
  ///
  /// Tags that are not SemVer versions are skipped, and so are prereleases unless
  /// `includePrereleases` is set. A failure is returned as ``UpdateCheckState/failed(_:)``, not
  /// thrown.
  public func check(
    currentVersion rawCurrentVersion: String,
    includePrereleases: Bool = false
  ) async -> UpdateCheckState {
    guard let currentVersion = SemanticVersion(rawCurrentVersion) else {
      return .failed(
        UpdateCheckFailure(
          reason: .invalidCurrentVersion,
          message: "Current app version is not SemVer: \(rawCurrentVersion)"
        )
      )
    }

    do {
      let candidate = try await latestTag(includePrereleases: includePrereleases)
      let info = UpdateInfo(
        tagName: candidate.tag.name,
        version: candidate.version,
        htmlURL: tagURL(candidate.tag.name)
      )
      if currentVersion < candidate.version { return .available(info) }
      if candidate.version < currentVersion {
        return .aheadOfLatestRelease(current: rawCurrentVersion, latest: candidate.tag.name)
      }
      return .upToDate(current: rawCurrentVersion, latest: candidate.tag.name)
    } catch is OnlyPrereleasesPublished {
      return .onlyPrereleases
    } catch let error as UpdateCheckerError {
      return .failed(UpdateCheckFailure(reason: error.reason, message: error.message))
    } catch {
      return .failed(UpdateCheckFailure(reason: .transport, message: error.localizedDescription))
    }
  }

  /// The tag with the highest version.
  ///
  /// - Throws: An error with ``UpdateCheckFailureReason/noValidTags`` when no tag is a version,
  ///   `OnlyPrereleasesPublished` when every version is a prerelease that is left out, or the error
  ///   of reading the tags.
  private func latestTag(includePrereleases: Bool) async throws -> Candidate {
    let tags = try await allTags()
    let versioned = tags.compactMap { tag -> Candidate? in
      SemanticVersion(tag.name).map { Candidate(tag: tag, version: $0) }
    }
    let candidates = versioned.filter { includePrereleases || $0.version.prerelease.isEmpty }
    guard let latest = candidates.max(by: { $0.version < $1.version }) else {
      if !versioned.isEmpty { throw OnlyPrereleasesPublished() }
      throw UpdateCheckerError(.noValidTags, "No release versions found")
    }
    return latest
  }

  /// Every tag of the repository, followed through the pages of the response.
  ///
  /// - Throws: An error with ``UpdateCheckFailureReason/paginationCycle`` when a page repeats, or
  ///   the error of reading a page.
  private func allTags() async throws -> [GitHubTag] {
    var tags: [GitHubTag] = []
    var nextURL: URL? = tagsURL
    var visited: Set<URL> = []

    while let pageURL = nextURL {
      guard visited.insert(pageURL).inserted else {
        throw UpdateCheckerError(.paginationCycle, "GitHub tag pagination contains a cycle")
      }

      let page = try await tagPage(url: pageURL)
      tags.append(contentsOf: page.tags)
      nextURL = try nextPageURL(response: page.response, currentURL: pageURL)
    }

    return tags
  }

  /// Reads one page of tags and its response.
  ///
  /// - Throws: An error with ``UpdateCheckFailureReason/invalidResponse`` or
  ///   ``UpdateCheckFailureReason/httpStatus(_:)``, or the error of the request.
  private func tagPage(url: URL) async throws -> (tags: [GitHubTag], response: HTTPURLResponse) {
    var request = URLRequest(url: url)
    request.timeoutInterval = Self.requestTimeoutSeconds
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("OpenJoystickDriver", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw UpdateCheckerError(.invalidResponse, "GitHub returned a non-HTTP response")
    }
    guard Self.httpSuccessStatusRange.contains(http.statusCode) else {
      throw UpdateCheckerError(
        .httpStatus(http.statusCode),
        "GitHub returned HTTP \(http.statusCode)"
      )
    }
    do { return (try JSONDecoder().decode([GitHubTag].self, from: data), http) } catch {
      throw UpdateCheckerError(.invalidResponse, error.localizedDescription)
    }
  }

  /// The URL of the next page, from the `Link` header of `response`; nil when there is none.
  ///
  /// - Throws: An error with ``UpdateCheckFailureReason/unsafePaginationLink`` when the link leaves
  ///   the scheme, host or port of the tags URL.
  private func nextPageURL(response: HTTPURLResponse, currentURL: URL) throws -> URL? {
    guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }

    for entry in link.split(separator: ",") {
      let fields = entry.split(separator: ";").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard let target = fields.first, target.hasPrefix("<"), target.hasSuffix(">"),
        fields.dropFirst().contains(where: { field in field == "rel=\"next\"" || field == "rel=next"
        })
      else { continue }

      let value = String(target.dropFirst().dropLast())
      guard let url = URL(string: value, relativeTo: currentURL)?.absoluteURL,
        ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
        url.scheme?.caseInsensitiveCompare(tagsURL.scheme ?? "") == .orderedSame,
        url.host?.caseInsensitiveCompare(tagsURL.host ?? "") == .orderedSame,
        url.port == tagsURL.port
      else {
        throw UpdateCheckerError(
          .unsafePaginationLink,
          "GitHub returned an unsafe tag pagination link"
        )
      }
      return url
    }
    return nil
  }

  /// The GitHub page of the tag `tagName`.
  private func tagURL(_ tagName: String) -> URL {
    repositoryURL.appendingPathComponent("tree").appendingPathComponent(tagName)
  }
}

/// Every version tag is a prerelease while prereleases are left out.
private struct OnlyPrereleasesPublished: Error {}

/// A failure of the update check with its reason.
private struct UpdateCheckerError: Error {
  /// Why the check failed.
  let reason: UpdateCheckFailureReason
  /// A description of the failure.
  let message: String
  /// Creates an error from a reason and a message.
  init(_ reason: UpdateCheckFailureReason, _ message: String) {
    self.reason = reason
    self.message = message
  }
}
