public import Foundation

/// A community validation of one mode of a controller record: a maintainer accepted the
/// `controller-validation.yml` issue that holds a guided check in which every control responded.
public struct ControllerValidation: Decodable, Equatable, Sendable {
  /// The number of the validation issue.
  public let issue: Int
  /// The `id` of the validated mode of the record.
  public let modeID: String
  /// The OJD version that ran the check.
  public let appVersion: String
  /// The day the maintainer accepted the validation, as `yyyy-MM-dd`.
  public let date: String

  /// The validation page: the issue on GitHub.
  public var issueURL: URL { ControllerLookup.repositoryURL(path: "issues/\(issue)") }

  /// Decodes `issue`, `mode`, `appVersion` and `date`; an unknown key, an `issue` below 1 or a
  /// `date` that is not `yyyy-MM-dd` is rejected.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["issue", "mode", "appVersion", "date"])
    issue = try container.decode(Int.self, for: "issue")
    modeID = try container.decode(String.self, for: "mode")
    appVersion = try container.decode(String.self, for: "appVersion")
    date = try container.decode(String.self, for: "date")
    func refuse(_ key: String, _ message: String) -> DecodingError {
      .dataCorrupted(
        .init(codingPath: decoder.codingPath + [DocumentKey(key)], debugDescription: message)
      )
    }
    guard issue >= 1 else { throw refuse("issue", "issue must be 1 or more") }
    guard date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
      throw refuse("date", "date must be yyyy-MM-dd")
    }
  }
}
