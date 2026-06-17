import Foundation
import OpenJoystickDriverKit
import Sparkle

@MainActor final class SparkleUpdateController: NSObject, SPUUpdaterDelegate {
  private enum SparkleErrorCode {
    // SUErrors.h
    static let noPublicDSAFoundError = 1  // SUNoPublicDSAFoundError
    static let insufficientSigningError = 2  // SUInsufficientSigningError
    static let insecureFeedURLError = 3  // SUInsecureFeedURLError
    static let invalidFeedURLError = 4  // SUInvalidFeedURLError
    static let appcastParseError = 1000  // SUAppcastParseError
    static let appcastError = 1002  // SUAppcastError
    static let runningFromDiskImageError = 1003  // SURunningFromDiskImageError
    static let resumeAppcastError = 1004  // SUResumeAppcastError
    static let runningTranslocatedError = 1005  // SURunningTranslocated
    static let downloadError = 2001  // SUDownloadError
    static let unarchivingError = 3000  // SUUnarchivingError
    static let signatureError = 3001  // SUSignatureError
    static let validationError = 3002  // SUValidationError
    static let fileCopyFailure = 4000  // SUFileCopyFailure
    static let authenticationFailure = 4001  // SUAuthenticationFailure
    static let missingUpdateError = 4002  // SUMissingUpdateError
    static let missingInstallerToolError = 4003  // SUMissingInstallerToolError
    static let relaunchError = 4004  // SURelaunchError
    static let installationError = 4005  // SUInstallationError
    static let agentInvalidationError = 4010  // SUAgentInvalidationError
    static let installationWriteNoPermissionError = 4012  // SUInstallationWriteNoPermissionError
    static let incorrectAPIUsageError = 5000  // SUIncorrectAPIUsageError
  }

  private enum SparkleNoUpdateReasonCode {
    // SPUNoUpdateFoundReason
    static let onLatestVersion = 1
    static let onNewerThanLatestVersion = 2
    static let systemIsTooOld = 3
    static let systemIsTooNew = 4
    static let hardwareDoesNotSupportARM64 = 5
  }

  private let bundle: Bundle
  private let stateHandler: @MainActor (UpdateCheckState) -> Void
  private var updaterController: SPUStandardUpdaterController?
  private var probeCompletionState: UpdateCheckState?
  private var shouldPresentStandardUpdateUI = false

  init(
    bundle: Bundle = .main,
    stateHandler: @escaping @MainActor (UpdateCheckState) -> Void = { _ in }
  ) {
    self.bundle = bundle
    self.stateHandler = stateHandler

    self.updaterController = nil
    super.init()

    guard Self.isConfigured(in: bundle) else { return }

    self.updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: self,
      userDriverDelegate: nil
    )
  }

  var isConfigured: Bool { updaterController != nil }

  func checkForUpdates(_ sender: Any? = nil) {
    guard let updater = updaterController?.updater else { return }
    guard !updater.sessionInProgress else {
      stateHandler(.failed("Update check already in progress."))
      return
    }

    probeCompletionState = .checking
    shouldPresentStandardUpdateUI = false
    stateHandler(.checking)
    updater.checkForUpdateInformation()
  }

  static func isConfigured(in bundle: Bundle) -> Bool {
    let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
    let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    return !(feedURL ?? "").isEmpty && !(publicKey ?? "").isEmpty
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    shouldPresentStandardUpdateUI = true
    probeCompletionState = .idle
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    probeCompletionState = noUpdateState(for: error as NSError)
  }

  func updater(
    _ updater: SPUUpdater,
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: Error?
  ) {
    if let error {
      probeCompletionState = .failed(Self.explicitMessage(for: error as NSError, bundle: bundle))
    }

    if let probeCompletionState { stateHandler(probeCompletionState) }

    let shouldPresentStandardUpdateUI = self.shouldPresentStandardUpdateUI
    self.shouldPresentStandardUpdateUI = false
    self.probeCompletionState = nil

    guard shouldPresentStandardUpdateUI else { return }
    DispatchQueue.main.async { [weak self] in self?.updaterController?.checkForUpdates(nil) }
  }

  private func noUpdateState(for error: NSError) -> UpdateCheckState {
    let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let reason = error.userInfo[SPUNoUpdateFoundReasonKey] as? Int
    switch reason {
    case SparkleNoUpdateReasonCode.onLatestVersion,
      SparkleNoUpdateReasonCode.onNewerThanLatestVersion:
      return .upToDate(appVersion)
    case SparkleNoUpdateReasonCode.systemIsTooOld:
      return .failed("Update feed has a newer version, but this macOS version is too old for it.")
    case SparkleNoUpdateReasonCode.systemIsTooNew:
      return .failed("Update feed has no build compatible with this macOS version yet.")
    case SparkleNoUpdateReasonCode.hardwareDoesNotSupportARM64:
      return .failed(
        "Update feed only offers Apple Silicon builds, but this Mac does not support ARM64."
      )
    default:
      return .failed(
        "No compatible update was found in the update feed for OpenJoystickDriver \(appVersion)."
      )
    }
  }

  private static func explicitMessage(for error: NSError, bundle: Bundle) -> String {
    let rootError = deepestUnderlyingError(in: error)

    if let networkMessage = networkMessage(for: rootError as NSError, bundle: bundle) {
      return networkMessage
    }

    if error.domain == SUSparkleErrorDomain {
      switch error.code {
      case SparkleErrorCode.insecureFeedURLError:
        return "Update feed URL is insecure: "
          + "\(feedURL(in: bundle) ?? "missing SUFeedURL"). Sparkle requires HTTPS."
      case SparkleErrorCode.invalidFeedURLError:
        return "Update feed URL is invalid: \(feedURL(in: bundle) ?? "missing SUFeedURL")."
      case SparkleErrorCode.noPublicDSAFoundError, SparkleErrorCode.insufficientSigningError:
        return "Sparkle public signing key is missing or invalid in SUPublicEDKey."
      case SparkleErrorCode.appcastParseError:
        return "Update feed could not be parsed from "
          + "\(feedURL(in: bundle) ?? "the configured SUFeedURL"). "
          + "The appcast XML is malformed or missing required Sparkle fields."
      case SparkleErrorCode.appcastError, SparkleErrorCode.resumeAppcastError:
        return fallbackMessage(
          prefix: "Failed to retrieve update feed from "
            + "\(feedURL(in: bundle) ?? "the configured SUFeedURL")",
          error: rootError
        )
      case SparkleErrorCode.runningFromDiskImageError, SparkleErrorCode.runningTranslocatedError:
        return "Updates cannot be installed from a disk image or translocated app. "
          + "Move OpenJoystickDriver.app into /Applications and launch it from there."
      case SparkleErrorCode.downloadError:
        return fallbackMessage(prefix: "Failed to download the update archive", error: rootError)
      case SparkleErrorCode.unarchivingError:
        return fallbackMessage(
          prefix: "Downloaded update archive could not be extracted",
          error: rootError
        )
      case SparkleErrorCode.signatureError, SparkleErrorCode.validationError:
        return fallbackMessage(
          prefix: "Downloaded update failed Sparkle signature validation",
          error: rootError
        )
      case SparkleErrorCode.installationWriteNoPermissionError:
        return fallbackMessage(
          prefix: "Updater does not have permission to replace \(bundle.bundleURL.path)",
          error: rootError
        )
      case SparkleErrorCode.installationError, SparkleErrorCode.fileCopyFailure,
        SparkleErrorCode.authenticationFailure, SparkleErrorCode.relaunchError,
        SparkleErrorCode.missingInstallerToolError, SparkleErrorCode.missingUpdateError,
        SparkleErrorCode.agentInvalidationError:
        return fallbackMessage(prefix: "Update installation failed", error: rootError)
      case SparkleErrorCode.incorrectAPIUsageError:
        return fallbackMessage(prefix: "Sparkle was invoked incorrectly", error: rootError)
      default: break
      }
    }

    return fallbackMessage(prefix: "Update check failed", error: rootError)
  }

  private static func networkMessage(for error: NSError, bundle: Bundle) -> String? {
    guard error.domain == NSURLErrorDomain else { return nil }

    let url =
      failingURL(in: error)?.absoluteString ?? feedURL(in: bundle) ?? "the configured SUFeedURL"
    switch error.code {
    case NSURLErrorNotConnectedToInternet:
      return "Could not reach update feed at \(url): this Mac appears to be offline."
    case NSURLErrorTimedOut: return "Timed out while contacting update feed at \(url)."
    case NSURLErrorCannotFindHost: return "Could not resolve update host for \(url)."
    case NSURLErrorCannotConnectToHost: return "Could not connect to update host for \(url)."
    case NSURLErrorNetworkConnectionLost:
      return "Network connection dropped while contacting update feed at \(url)."
    case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
      NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
      NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
      NSURLErrorClientCertificateRequired:
      return fallbackMessage(
        prefix: "TLS validation failed for update feed at \(url)",
        error: error
      )
    case NSURLErrorBadURL: return "Update feed URL is malformed: \(url)."
    default:
      return fallbackMessage(prefix: "Could not retrieve update feed from \(url)", error: error)
    }
  }

  private static func fallbackMessage(prefix: String, error: NSError) -> String {
    let reason = [
      error.localizedFailureReason, error.localizedDescription,
      (error.userInfo[NSDebugDescriptionErrorKey] as? String),
    ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }

    guard let reason else { return prefix }
    if reason.caseInsensitiveCompare(prefix) == .orderedSame || reason.hasPrefix(prefix) {
      return reason
    }
    return "\(prefix): \(reason)"
  }

  private static func deepestUnderlyingError(in error: NSError) -> NSError {
    var current = error
    var seenDomainsAndCodes = Set<String>()
    while let next = current.userInfo[NSUnderlyingErrorKey] as? NSError {
      let key = "\(next.domain)#\(next.code)"
      if seenDomainsAndCodes.contains(key) { break }
      seenDomainsAndCodes.insert(key)
      current = next
    }
    return current
  }

  private static func feedURL(in bundle: Bundle) -> String? {
    (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
  }

  private static func failingURL(in error: NSError) -> URL? {
    if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL { return url }
    if let urlString = error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
      return URL(string: urlString)
    }
    return nil
  }
}
