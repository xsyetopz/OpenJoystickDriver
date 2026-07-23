import Foundation

struct CompatibilityOutputStatus: Sendable, Equatable {
  let state: CompatibilityOutputState
  let detail: String?
  let diagnostic: String?

  init(enabled: Bool?, status: String?) {
    let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let normalizedStatus, normalizedStatus.hasPrefix("error:") {
      self.state = .error
      self.detail = nil
      let message = normalizedStatus.dropFirst("error:".count).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      self.diagnostic = message.isEmpty ? normalizedStatus : message
      return
    }

    self.detail = normalizedStatus
    self.diagnostic = nil
    switch (enabled, normalizedStatus) {
    case (.some(true), _): self.state = .enabled
    case (.some(false), .some("off")): self.state = .disabled
    default: self.state = .unavailable
    }
  }

  static let unavailable = Self(enabled: nil, status: nil)
}
