public import Foundation

/// The page that Lookup opens for a controller model.
public enum ControllerLookup {
  /// The address of `path` in the project's GitHub repository, with an optional query and fragment.
  static func repositoryURL(
    path: String,
    query: [URLQueryItem]? = nil,
    fragment: String? = nil
  ) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/xsyetopz/OpenJoystickDriver/\(path)"
    components.queryItems = query
    components.fragment = fragment
    guard let url = components.url else {
      preconditionFailure("a fixed host and an escaped path form an address")
    }
    return url
  }

  /// The address Lookup opens for `model`.
  ///
  /// A model with a record opens the page of the supported controllers, at the Community-Verified
  /// tier when the record holds a validation. A model with no record opens a GitHub issue search
  /// for its `VVVV:PPPP`.
  public static func url(for model: ControllerModelID, record: ControllerRecord?) -> URL {
    guard let record else {
      return repositoryURL(
        path: "issues",
        query: [URLQueryItem(name: "q", value: model.description)]
      )
    }
    return repositoryURL(
      path: "wiki/Supported-Controllers",
      fragment: record.validations.isEmpty ? nil : "community-verified"
    )
  }
}
