import Foundation

package enum ExtensionBundleState: Sendable, Equatable {
  case present
  case missing
  case invalid(String)
}

package struct ExtensionVersionFacts: Sendable, Equatable {
  package let bundleIdentifier: String
  package let shortVersion: String
  package let buildVersion: String

  package init(bundleIdentifier: String, shortVersion: String, buildVersion: String) {
    self.bundleIdentifier = bundleIdentifier
    self.shortVersion = shortVersion
    self.buildVersion = buildVersion
  }
}

package enum ExtensionRegistrationState: Sendable, Equatable {
  case active(String)
  case inactive(String)
  case absent
  case unavailable(String)
}

package struct ExtensionStatus: Sendable, Equatable {
  package let bundle: ExtensionBundleState
  package let registration: ExtensionRegistrationState
  package let embedded: ExtensionVersionFacts?
  package let installed: ExtensionVersionFacts?

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

  /// The `systemextensionsctl` record, the unexpected bundle identifier, or the reason the state
  /// is unavailable; nil when there is nothing to add. A record wins over an invalid bundle.
  package var detail: String? {
    switch (bundle, registration) {
    case (_, .active(let record)), (_, .inactive(let record)): record
    case (_, .unavailable(let reason)): reason
    case (.invalid(let identifier), _): identifier
    default: nil
    }
  }

  package static let unavailable = Self(
    bundle: .missing,
    registration: .unavailable("System-extension status has not been checked.")
  )
}

package enum SystemExtensionSetupRequestResult: Sendable, Equatable {
  case active
  case inactive
  case awaitingApproval
  case failed
  case cancelled
  case timedOut
}
