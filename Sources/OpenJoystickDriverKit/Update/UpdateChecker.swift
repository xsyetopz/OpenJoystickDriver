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
  private static let httpSuccessStatusRange = 200...299

  public static var defaultTagsURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.path = "/repos/xsyetopz/OpenJoystickDriver/tags"
    components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
    return components.url ?? URL(fileURLWithPath: "/")
  }

  public static var defaultRepositoryURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/xsyetopz/OpenJoystickDriver"
    return components.url ?? URL(fileURLWithPath: "/")
  }

  private struct GitHubTag: Decodable { let name: String }

  private struct Candidate {
    let tag: GitHubTag
    let version: SemanticVersion
  }

  public let tagsURL: URL
  public let repositoryURL: URL
  public let session: URLSession

  public init(
    tagsURL: URL = Self.defaultTagsURL,
    repositoryURL: URL = Self.defaultRepositoryURL,
    session: URLSession = .shared
  ) {
    self.tagsURL = tagsURL
    self.repositoryURL = repositoryURL
    self.session = session
  }

  public func check(currentVersion rawCurrentVersion: String, includePrereleases: Bool = false)
    async -> UpdateCheckState
  {
    guard let currentVersion = SemanticVersion(rawCurrentVersion) else {
      return .failed("Current app version is not SemVer: \(rawCurrentVersion)")
    }

    do {
      let candidate = try await latestTag(includePrereleases: includePrereleases)
      let info = UpdateInfo(
        tagName: candidate.tag.name,
        version: candidate.version,
        htmlURL: tagURL(candidate.tag.name)
      )
      return candidate.version > currentVersion ? .available(info) : .upToDate(candidate.tag.name)
    } catch let error as UpdateCheckerError { return .failed(error.message) } catch {
      return .failed(error.localizedDescription)
    }
  }

  private func latestTag(includePrereleases: Bool) async throws -> Candidate {
    let tags = try await allTags()
    let candidates = tags.compactMap { tag -> Candidate? in
      guard let version = SemanticVersion(tag.name) else { return nil }
      guard includePrereleases || version.prerelease.isEmpty else { return nil }
      return Candidate(tag: tag, version: version)
    }
    guard let latest = candidates.max(by: { $0.version < $1.version }) else {
      let channel = includePrereleases ? "" : " stable"
      throw UpdateCheckerError("No\(channel) SemVer GitHub tags found")
    }
    return latest
  }

  private func allTags() async throws -> [GitHubTag] {
    var tags: [GitHubTag] = []
    var nextURL: URL? = tagsURL
    var visited: Set<URL> = []

    while let pageURL = nextURL {
      guard visited.insert(pageURL).inserted else {
        throw UpdateCheckerError("GitHub tag pagination contains a cycle")
      }

      let page = try await tagPage(url: pageURL)
      tags.append(contentsOf: page.tags)
      nextURL = try nextPageURL(response: page.response, currentURL: pageURL)
    }

    return tags
  }

  private func tagPage(url: URL) async throws -> (tags: [GitHubTag], response: HTTPURLResponse) {
    var request = URLRequest(url: url)
    request.timeoutInterval = Self.requestTimeoutSeconds
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("OpenJoystickDriver", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw UpdateCheckerError("GitHub returned a non-HTTP response")
    }
    guard Self.httpSuccessStatusRange.contains(http.statusCode) else {
      throw UpdateCheckerError("GitHub returned HTTP \(http.statusCode)")
    }
    return (try JSONDecoder().decode([GitHubTag].self, from: data), http)
  }

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
      else { throw UpdateCheckerError("GitHub returned an unsafe tag pagination link") }
      return url
    }
    return nil
  }

  private func tagURL(_ tagName: String) -> URL {
    repositoryURL.appendingPathComponent("tree").appendingPathComponent(tagName)
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
