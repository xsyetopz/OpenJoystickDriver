import Foundation
import OpenJoystickDriverKit

extension EndpointServer {
  /// The kinds that a welcomed client may send first: a request to answer, a subscription, or a
  /// feed.
  static let requestKinds = ["Subscription", "FeedRequest", "ProfileRequest", "ModList", "OutputRequest"]

  /// Answers one request of `kind` from its `line` and tells whether the connection goes on.
  ///
  /// A request that needs a scope the client lacks, or a line that is not a valid request of its
  /// kind, ends the connection. A request that the service refuses is answered with a `Status`
  /// failure that carries the code `ojd` prints for it, and the connection stays open.
  func perform(
    _ kind: EndpointRequest.Kind,
    line: Data,
    on connection: EndpointConnection
  ) -> Bool {
    let scope: EndpointScope = kind == .modList ? .read : .control
    guard connection.session?.scopes.contains(scope) == true else {
      connection.close(
        EndpointError(
          code: .notGranted,
          message: "\(kind.rawValue) needs the \(scope.rawValue.lowercased()) scope."
        )
      )
      return false
    }
    if kind == .modList {
      connection.send(EndpointMods(mods: modStore.entries()))
      return !connection.isClosing
    }
    let automation = automation
    do {
      if kind == .outputRequest {
        guard let request = try? JSONDecoder().decode(EndpointOutputRequest.self, from: line) else {
          connection.close(Self.invalid("The message is not a valid request of its kind."))
          return false
        }
        let result = try Self.waitFor(connection) { try await request.run(on: automation) }
        connection.send(EndpointOutputResult(result))
        return !connection.isClosing
      }
      guard let request = try? JSONDecoder().decode(EndpointProfileRequest.self, from: line) else {
        connection.close(Self.invalid("The message is not a valid request of its kind."))
        return false
      }
      let profile = try Self.waitFor(connection) { try await request.run(on: automation) }
      connection.send(EndpointProfileResult(profile: profile))
    } catch {
      connection.send(Self.refusal(error))
    }
    return !connection.isClosing
  }

  /// The `Status` failure that reports `error` with the code `ojd` prints for it.
  static func refusal(_ error: any Error) -> EndpointError {
    let failure = error as? CodedFailure ?? CodedFailure(.serviceRequestFailed, error.localizedDescription)
    return EndpointError(code: failure.id, message: failure.message)
  }
}

extension EndpointOutputRequest {
  /// Sends the output as `ojd controller` does, with its code for an output the controller lacks.
  func run(on automation: any AutomationService) async throws -> AutomationOutputResult {
    switch output {
    case .rumble(let intensities, let seconds):
      try await automation.sendOutput(
        [ControllerOutput.rumble(intensities, seconds: seconds)],
        to: controller,
        requestedMotors: intensities.activeMotors
      )
    case .player(let indicator):
      try await automation.sendOutput([ControllerOutput.player(indicator)], to: controller)
    case .light(let color, let brightness):
      try await automation.sendOutput(
        ControllerOutput.light(color: color, brightness: brightness),
        to: controller
      )
    }
  }
}

extension EndpointProfileRequest {
  /// Does what the request asks, with the code of `ojd profile` and the App Intents.
  func run(on automation: any AutomationService) async throws -> AutomationProfile {
    if case .set(let key, let value) = operation {
      return try await automation.setProfileValue(profile: profile, key: key, value: value)
    }
    let id = try profile.resolve(in: try await automation.getRemappingSnapshot().profiles).id
    return switch operation {
    case .activate: try await automation.activateProfile(id: id)
    default: try await automation.deactivateProfile(id: id)
    }
  }
}
