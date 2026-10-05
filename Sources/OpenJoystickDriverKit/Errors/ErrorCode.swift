import Foundation

/// The stable error codes of OpenJoystickDriver, listed in `Resources/ErrorCodes.json`.
///
/// A code never changes meaning and is never reused. Look codes up on the wiki page `Error-Codes`.
public enum ErrorCode: String, Codable, Sendable, CaseIterable {
  case endpointDisabled = "E1001"
  case notGranted = "E1002"
  case unsupportedProtocol = "E1003"
  case invalidMessage = "E1004"
  case tooManyConnections = "E1005"
  case revoked = "E1006"
  case tooSlow = "E1007"
  case tooManyFeeds = "E1008"
  case feedClosed = "E1009"

  /// The part of the product that raises a code; the first digit of the number.
  public enum Domain: String, Sendable {
    case endpoint
    case commandLine = "cli"
    case remapping
  }

  public var domain: Domain {
    switch self {
    case .endpointDisabled, .notGranted, .unsupportedProtocol, .invalidMessage,
      .tooManyConnections, .revoked, .tooSlow, .tooManyFeeds, .feedClosed:
      .endpoint
    }
  }

  /// What went wrong and how to fix it, in the language of the user.
  public var localizedExplanation: String {
    Localization().string("error.\(rawValue)", defaultValue: nil)
  }
}
