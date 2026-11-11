import Foundation

/// Everything `ojd explain` prints for an error code.
///
/// The app's Explain Error Code sheet shows the same facts.
public struct ErrorCodeFacts: Equatable, Sendable {
  /// The code, such as `E2004`.
  public let code: String
  /// The raw name of the area that raises the code.
  public let domain: String
  /// The localized name of the area that raises the code.
  public let area: String
  /// The localized explanation: what went wrong and how to fix it.
  public let explanation: String
  /// The exit status of `ojd` for a command-line code; nil for other areas.
  public let exitCode: Int32?
  /// The RPC wire value of a remapping code; nil for other areas.
  public let wire: String?
}

extension ErrorCode {
  /// The exit status of `ojd` when it fails with this code; `Resources/ErrorCodes.plist` lists it as
  /// `exitCode`.
  ///
  /// A code of another area, such as a remapping code, is a plain failure (1).
  public var commandLineExitStatus: Int32 {
    switch self {
    case .unknownCommand, .usage, .confirmationRequired, .noAccessScope, .duplicateTokenName,
      .invalidTokenName, .invalidWebOrigin, .webPortUnavailable, .controlScopeWithOrigins:
      64
    case .serviceUnavailable, .requestListenerStopped, .noApplicationAnswered: 69
    case .permissionMissing, .notificationsDenied: 77
    case .installedCLIFailed: 127
    default: 1
    }
  }

  /// The exit statuses `ojd` fails with: the status of each command-line code.
  /// `wiki/Command-Line.md` documents each of them.
  public static var commandLineExitStatuses: Set<Int32> {
    Set(allCases.filter { $0.domain == .commandLine }.map(\.commandLineExitStatus))
  }

  /// The facts about the code that `ojd explain` prints.
  public var facts: ErrorCodeFacts {
    let localization = Localization()
    return ErrorCodeFacts(
      code: rawValue,
      domain: domain.rawValue,
      area: localization.string(domain.areaKey),
      explanation: localizedExplanation,
      exitCode: domain == .commandLine ? commandLineExitStatus : nil,
      wire: domain == .remapping
        ? ApplicationServiceRemappingRPCError.Code.allCases.first { $0.errorCode == self }?.rawValue
        : nil
    )
  }
}
