enum ExtensionBundleState: Sendable, Equatable {
  case present
  case missing
  case invalid(String)
}
