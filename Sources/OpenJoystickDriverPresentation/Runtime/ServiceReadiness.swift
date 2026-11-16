import Foundation
import OpenJoystickDriverKit

/// What a person reads about the background service: it runs, it waits, or it cannot be used.
enum ServiceReadiness: Equatable, Sendable, CaseIterable {
  /// The first read of the service has not finished.
  case checking
  /// The service answers and runs the app's build.
  case running
  /// The service does not answer.
  case stopped
  /// The service's request listener stopped.
  case listenerStopped
  /// The service answered, but the app could not read its status.
  case readFailed
  /// The service has no login-item registration, and it does not answer.
  case notInstalled
  /// macOS waits for the user to approve the login item, and the service does not answer.
  case needsApproval
  /// The service runs another build than the app.
  case versionMismatch

  /// The SF Symbol of the state; every state has its own base shape, so the states differ without
  /// color.
  var symbolName: String {
    switch self {
    case .checking: return "clock.fill"
    case .running: return "checkmark.circle.fill"
    case .stopped: return "stop.circle.fill"
    case .listenerStopped: return "bolt.slash.fill"
    case .readFailed: return "exclamationmark.octagon.fill"
    case .notInstalled: return "square.and.arrow.down.fill"
    case .needsApproval: return "hand.raised.fill"
    case .versionMismatch: return "arrow.triangle.2.circlepath"
    }
  }

  /// The localization key of the one sentence that says what the state means.
  var messageKey: String {
    switch self {
    case .checking: return "ui.service.state.checking.message"
    case .running: return "ui.service.state.running.message"
    case .stopped: return "ui.banner.service.title"
    case .listenerStopped: return "ui.service.state.listenerStopped.message"
    case .readFailed: return "ui.service.state.readFailed.message"
    case .notInstalled: return "ui.service.state.notInstalled.message"
    case .needsApproval: return "ui.service.state.needsApproval.message"
    case .versionMismatch: return "ui.service.state.versionMismatch.message"
    }
  }

  /// Whether the state asks something of the user.
  var isProblem: Bool { self != .checking && self != .running }

  /// Whether the state stops every controller.
  var isFailure: Bool {
    switch self {
    case .stopped, .listenerStopped, .readFailed, .notInstalled: return true
    case .checking, .running, .needsApproval, .versionMismatch: return false
    }
  }

  /// Returns the state of the service.
  ///
  /// The login item explains a service that does not answer; it says nothing about one that does.
  static func resolve(_ input: ServiceReadinessInput) -> Self {
    switch input.status {
    case .loading: return .checking
    case .available(let presentation):
      if let build = presentation.serviceBuild, !build.matches(input.appBuild) {
        return .versionMismatch
      }
      return .running
    case .error: return input.listenerStopped ? .listenerStopped : .readFailed
    case .unavailable:
      if input.listenerStopped { return .listenerStopped }
      switch input.registration {
      case .notRegistered, .notFound: return .notInstalled
      case .requiresApproval: return .needsApproval
      case .enabled, nil: return .stopped
      }
    }
  }

  /// The login-item registration that macOS reports for a service that does not answer; nil
  /// before macOS 13, and for a status that explains itself, which never asks the host.
  static func currentRegistration(
    for status: RuntimeStatusState
  ) -> ApplicationServiceRegistrationStatus? {
    guard case .unavailable = status, #available(macOS 13.0, *) else { return nil }
    return PlatformHosts.current.mainAppRegistration.status
  }
}

/// The facts that decide the ``ServiceReadiness``.
struct ServiceReadinessInput: Equatable, Sendable {
  /// The service status as the views hold it.
  let status: RuntimeStatusState
  /// Whether the service's request listener stopped.
  let listenerStopped: Bool
  /// The login-item registration, or nil when it is unknown.
  let registration: ApplicationServiceRegistrationStatus?
  /// The build of the running app.
  let appBuild: BuildIdentity

  /// Creates the input from its facts.
  init(
    status: RuntimeStatusState,
    listenerStopped: Bool,
    registration: ApplicationServiceRegistrationStatus?,
    appBuild: BuildIdentity = ApplicationVersion.buildIdentity
  ) {
    self.status = status
    self.listenerStopped = listenerStopped
    self.registration = registration
    self.appBuild = appBuild
  }
}

extension BuildIdentity {
  /// Whether both builds have the same release, build number and commit.
  fileprivate func matches(_ other: Self) -> Bool {
    semanticVersion == other.semanticVersion && appBundleVersion == other.appBundleVersion
      && sourceCommit == other.sourceCommit
  }
}
