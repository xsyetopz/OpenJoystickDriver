import Foundation

/// Whether the app bundle holds the DriverKit extension.
package enum ExtensionBundleState: Sendable, Equatable {
  /// The extension is in the bundle under its expected bundle identifier.
  case present
  /// The bundle holds no extension.
  case missing
  /// The extension in the bundle has another bundle identifier; the value is that identifier, or a
  /// note that it has none.
  case invalid(String)
}

/// The version of a DriverKit extension bundle.
package struct ExtensionVersionFacts: Sendable, Equatable {
  /// The extension's bundle identifier.
  package let extensionID: String
  /// The release version of the extension.
  package let shortVersion: String
  /// The build version of the extension.
  package let buildVersion: String

  /// Creates facts from their values.
  package init(extensionID: String, shortVersion: String, buildVersion: String) {
    self.extensionID = extensionID
    self.shortVersion = shortVersion
    self.buildVersion = buildVersion
  }
}

/// How `systemextensionsctl` lists the extension.
package enum ExtensionRegistrationState: Sendable, Equatable {
  /// The extension is activated and enabled; the value is its line of the listing.
  case active(String)
  /// The listing has the extension in another state; the value is its lines.
  case inactive(String)
  /// The listing does not have the extension.
  case absent
  /// The listing could not be read; the value is the reason.
  case unavailable(String)
}

/// Where the DriverKit extension is in the bundle and in the system.
package struct ExtensionStatus: Sendable, Equatable {
  /// Whether the app bundle holds the extension.
  package let bundle: ExtensionBundleState
  /// How `systemextensionsctl` lists the extension.
  package let registration: ExtensionRegistrationState
  /// The version of the extension in the app bundle; nil when it cannot be read.
  package let embedded: ExtensionVersionFacts?
  /// The version of the extension the system lists; nil when none is listed or it cannot be read.
  package let installed: ExtensionVersionFacts?

  /// Creates a status from its values.
  package init(
    bundle: ExtensionBundleState,
    registration: ExtensionRegistrationState,
    embedded: ExtensionVersionFacts? = nil,
    installed: ExtensionVersionFacts? = nil
  ) {
    self.bundle = bundle
    self.registration = registration
    self.embedded = embedded
    self.installed = installed
  }

  /// The `systemextensionsctl` record, the unexpected bundle identifier, or the reason the state is
  /// unavailable; nil when there is nothing to add.
  ///
  /// A record wins over an invalid bundle.
  package var detail: String? {
    switch (bundle, registration) {
    case (_, .active(let record)), (_, .inactive(let record)): record
    case (_, .unavailable(let reason)): reason
    case (.invalid(let identifier), _): identifier
    default: nil
    }
  }

  /// A status for when nothing has been checked: no extension in the bundle and an unavailable
  /// registration.
  package static let unavailable = Self(
    bundle: .missing,
    registration: .unavailable("System-extension status has not been checked.")
  )
}

/// The system's answer to a request to activate or deactivate the extension.
package enum SystemExtensionSetupRequestResult: Sendable, Equatable {
  /// The extension is active.
  case active
  /// The extension is not active.
  case inactive
  /// The system waits for the user to approve the extension.
  case awaitingApproval
  /// The request failed.
  case failed
  /// The request was cancelled.
  case cancelled
  /// The system did not answer in time.
  case timedOut
}
