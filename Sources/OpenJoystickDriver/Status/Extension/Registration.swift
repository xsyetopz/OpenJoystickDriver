enum ExtensionRegistrationState: Sendable, Equatable {
  case active(String)
  case inactive(String)
  case absent
  case unavailable(String)
}
