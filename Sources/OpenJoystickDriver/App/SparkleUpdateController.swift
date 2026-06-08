import Foundation
import Sparkle

@MainActor final class SparkleUpdateController {
  private let updaterController: SPUStandardUpdaterController?

  init(bundle: Bundle = .main) {
    guard Self.isConfigured(in: bundle) else {
      self.updaterController = nil
      return
    }

    self.updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  var isConfigured: Bool { updaterController != nil }

  func checkForUpdates(_ sender: Any? = nil) {
    updaterController?.checkForUpdates(sender)
  }

  static func isConfigured(in bundle: Bundle) -> Bool {
    let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
    let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    return !(feedURL ?? "").isEmpty && !(publicKey ?? "").isEmpty
  }
}
