import OpenJoystickDriverKit

struct RuntimeCompatibilityStatus: Sendable, Equatable {
  let identity: CompatibilityIdentity?
  let diagnostic: String?

  init(rawValue: String?) {
    self.identity = rawValue.flatMap(CompatibilityIdentity.init(rawValue:))
    if let rawValue, identity == nil {
      self.diagnostic = "Unknown compatibility identity: \(rawValue)"
    } else {
      self.diagnostic = nil
    }
  }

  static let unavailable = Self(rawValue: nil)
}
