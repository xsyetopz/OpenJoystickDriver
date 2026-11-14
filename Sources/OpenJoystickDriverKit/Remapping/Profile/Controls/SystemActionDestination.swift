import Foundation

extension RemappingSystemActionKind {
  /// The performer call that the action makes.
  fileprivate var request: RemappingSystemActionRequest {
    switch self {
    case .missionControl: .missionControl
    case .launchpad: .launchpad
    case .screenshot: .screenshot
    case .lockScreen: .lockScreen
    case .showDesktop: .showDesktop
    }
  }
}

extension RemappingDestination {
  /// The performer call that a press or release of the destination makes, or `nil` for none.
  ///
  /// A system key follows its source; every other action fires on the press.
  func systemActionRequest(isDown: Bool) -> RemappingSystemActionRequest? {
    switch self {
    case .systemKey(let key): return .key(key, pressed: isDown)
    case .systemAction(let action): return isDown ? action.request : nil
    case .openApplication(let identifier): return isDown ? .openApplication(identifier) : nil
    case .openURL(let url): return isDown ? .openURL(url) : nil
    case .runShortcut(let name): return isDown ? .runShortcut(name) : nil
    case .typeText(let text): return isDown ? .typeText(text) : nil
    default: return nil
    }
  }

  /// Whether the destination is a system action that fires on a press, so it takes press
  /// behaviors only.
  var isSystemTrigger: Bool {
    switch self {
    case .systemAction, .openApplication, .openURL, .runShortcut, .typeText: true
    default: false
    }
  }

  /// The name that a validation error gives for an invalid system action, or `nil` when the
  /// destination is not one or is valid.
  var invalidSystemActionName: String? {
    switch self {
    case .openApplication(let identifier): return identifier.isEmpty ? "OpenApplication" : nil
    case .openURL(let text):
      guard let scheme = URL(string: text)?.scheme, scheme.lowercased() != "file" else {
        return "OpenURL"
      }
      return nil
    case .runShortcut(let name): return (1...50).contains(name.count) ? nil : "RunShortcut"
    case .typeText(let text): return (1...128).contains(text.count) ? nil : "TypeText"
    default: return nil
    }
  }
}
