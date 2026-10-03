import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

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
      }
    )
  }

  /// Shared by every dispatcher, because the factory accepts commands from one connection only.
  /// Nil when the app bundles no extension, so devices use `IOHIDUserDevice` directly.
  nonisolated static let hidFactoryPublisher: DriverKitHIDFactoryPublisher? =
    ExtensionProbe.bundleState(in: Bundle.main.bundleURL) == .present
    ? DriverKitHIDFactoryPublisher() : nil

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
      devicePublisher: hidFactoryPublisher,
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
