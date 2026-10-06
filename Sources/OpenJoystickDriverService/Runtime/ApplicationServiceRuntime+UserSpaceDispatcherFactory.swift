import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceRuntime {
  /// Builds the automatic dispatcher, which applies ownership and session policy per controller
  /// and creates one IOHID-backed user-space dispatcher per selected profile.
  nonisolated static func makeAutomaticUserSpaceDispatcher(
    context: UserSpaceDispatcherFactoryContext
  ) throws -> any VirtualOutputDispatching {
    let overrides = context.profileOverrides
    return AutomaticUserSpaceOutputDispatcher(
      deviceManager: context.deviceManager,
      builder: { profileID in
        let profile = try profileID.makeProfile()
        return try makeUserSpaceOutputDispatcher(
          profile: profile.identity,
          format: profile.reportFormat,
          context: context
        )
      },
      overrideProvider: {
        overrides.override(vendorID: $0.vendorID, productID: $0.productID, unit: $0.unitIdentifier)
      },
      identityProvider: {
        overrides.persona(vendorID: $0.vendorID, productID: $0.productID, unit: $0.unitIdentifier)?
          .identity
      },
      identityBuilder: { profileID, identity in
        let profile = try profileID.makeProfile()
        return try makeUserSpaceOutputDispatcher(
          profile: profile.identity.applying(identity),
          format: profile.reportFormat,
          context: context
        )
      }
    )
  }

  /// Builds the device of one `ojd virtual feed`, which reports its output commands to the feed
  /// instead of a physical controller.
  nonisolated static func makeVirtualFeedDevice(
    profileID: VirtualHIDProfileID,
    onOutputCommand: @escaping UserSpaceOutputDispatcher.OutputCommandHandler
  ) throws -> any VirtualFeedDevice {
    let profile = try profileID.makeProfile()
    return try UserSpaceOutputDispatcher(
      profile: profile.identity,
      format: profile.reportFormat,
      onOutputCommand: onOutputCommand
    )
  }

  /// Each profile's backend publishes directly and routes output commands through the
  /// feedback gate.
  nonisolated private static func makeUserSpaceOutputDispatcher(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    context: UserSpaceDispatcherFactoryContext
  ) throws -> UserSpaceOutputDispatcher {
    let feedbackGate = context.feedbackGate
    let outputHandler: UserSpaceOutputDispatcher.OutputCommandHandler = { identifier, command in
      feedbackGate.submit(identifier: identifier, command: command)
    }

    return try UserSpaceOutputDispatcher(
      profile: profile,
      format: format,
      onOutputCommand: outputHandler
    ) { identifier in
      _ = await feedbackGate.quiesceAndNeutralize(
        [identifier],
        timeout: context.timeouts.feedbackNanoseconds,
        clock: context.clock,
        resumeWhenComplete: true
      )
    }
  }
}
