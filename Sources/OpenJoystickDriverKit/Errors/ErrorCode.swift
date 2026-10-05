import Foundation

/// The stable error codes of OpenJoystickDriver, listed in `Resources/ErrorCodes.json`.
///
/// A code never changes meaning and is never reused. Look codes up on the wiki page `Error-Codes`.
///
/// The E3xxx cases carry the names of `ApplicationServiceRemappingRPCError.Code`, except
/// `remappingUnexpected`, because `unexpected` names E2001. Case names are unique across areas.
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
  case unexpected = "E2001"
  case unknownCommand = "E2002"
  case usage = "E2003"
  case serviceUnavailable = "E2004"
  case serviceTimeout = "E2005"
  case serviceRequestFailed = "E2006"
  case peerRejected = "E2007"
  case permissionMissing = "E2008"
  case confirmationRequired = "E2009"
  case aborted = "E2010"
  case invalidInputFile = "E2011"
  case notFound = "E2012"
  case controllerRequestFailed = "E2013"
  case installationProblem = "E2014"
  case systemRequestFailed = "E2015"
  case fileAccessFailed = "E2016"
  case unsignedClient = "E2017"
  case diagnoseFailed = "E2018"
  case updateCheckFailed = "E2019"
  case staleInstallation = "E2020"
  case installedCLIFailed = "E2021"
  case controllerUnavailable = "E3001"
  case joyConPairUnavailable = "E3002"
  case motionUnavailable = "E3003"
  case argumentTooLarge = "E3004"
  case corruptLibrary = "E3005"
  case duplicateName = "E3006"
  case invalidArguments = "E3007"
  case invalidProfile = "E3008"
  case librarySizeExceeded = "E3009"
  case profileAlreadyExists = "E3010"
  case profileUpdateConflict = "E3011"
  case profileCountExceeded = "E3012"
  case profileNotFound = "E3013"
  case responseEncodingFailed = "E3014"
  case responseTooLarge = "E3015"
  case routerEngineUnavailable = "E3016"
  case routerLibraryAndEngineUnavailable = "E3017"
  case routerLibraryUnavailable = "E3018"
  case routerShutDown = "E3019"
  case transactionUnreconciled = "E3020"
  case unreadableLibrary = "E3021"
  case profileRecoveryRequired = "E3022"
  case unwritableLibrary = "E3023"
  case remappingUnexpected = "E3024"

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
    case .unexpected, .unknownCommand, .usage, .serviceUnavailable, .serviceTimeout,
      .serviceRequestFailed, .peerRejected, .permissionMissing, .confirmationRequired, .aborted,
      .invalidInputFile, .notFound, .controllerRequestFailed, .installationProblem,
      .systemRequestFailed, .fileAccessFailed, .unsignedClient, .diagnoseFailed,
      .updateCheckFailed, .staleInstallation, .installedCLIFailed:
      .commandLine
    case .controllerUnavailable, .joyConPairUnavailable, .motionUnavailable, .argumentTooLarge,
      .corruptLibrary, .duplicateName, .invalidArguments, .invalidProfile, .librarySizeExceeded,
      .profileAlreadyExists, .profileUpdateConflict, .profileCountExceeded, .profileNotFound,
      .responseEncodingFailed, .responseTooLarge, .routerEngineUnavailable,
      .routerLibraryAndEngineUnavailable, .routerLibraryUnavailable, .routerShutDown,
      .transactionUnreconciled, .unreadableLibrary, .profileRecoveryRequired, .unwritableLibrary,
      .remappingUnexpected:
      .remapping
    }
  }

  /// What went wrong and how to fix it, in the language of the user.
  public var localizedExplanation: String {
    Localization().string("error.\(rawValue)", defaultValue: nil)
  }
}
