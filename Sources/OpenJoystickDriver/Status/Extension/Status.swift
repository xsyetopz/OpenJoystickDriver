struct ExtensionStatus: Sendable, Equatable {
  let bundle: ExtensionBundleState
  let registration: ExtensionRegistrationState

  static let unavailable = Self(
    bundle: .missing,
    registration: .unavailable("System-extension status has not been checked.")
  )
}
