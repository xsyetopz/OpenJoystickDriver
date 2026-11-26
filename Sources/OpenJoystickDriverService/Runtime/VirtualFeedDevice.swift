import Foundation
import OpenJoystickDriverKit

/// The virtual controller one feed publishes.
protocol VirtualFeedDevice: AnyObject, Sendable {
  /// Publishes the virtual controller of `identifier`.
  ///
  /// - Throws: The failure to create the virtual device.
  func activate(controller identifier: LogicalControllerID) async throws
  /// Updates the virtual controller of `identifier` to `state`.
  func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws
  /// Removes the virtual controller.
  func close() async
}

extension UserSpaceOutputDispatcher: VirtualFeedDevice {}

/// Builds the device for a feed; the handler receives the host's output commands.
typealias VirtualFeedDeviceFactory =
  @Sendable (VirtualHIDProfileID, @escaping UserSpaceOutputDispatcher.OutputCommandHandler)
  throws -> any VirtualFeedDevice

/// Who opened a feed; each pool has its own `VirtualFeedRegistry.maximumFeeds`, so endpoint
/// clients cannot take the feeds of `ojd virtual feed`.
enum VirtualFeedPool: Hashable {
  /// A feed that an endpoint client opened.
  case endpoint
  /// The local service RPC, which `ojd virtual feed` uses.
  case rpc
}

/// Why a feed cannot be opened.
enum VirtualFeedError: LocalizedError, Equatable {
  /// The profile name is not a virtual HID profile.
  case unknownProfile(String)
  /// The pool already holds the most feeds, with that limit.
  case tooManyFeeds(Int)
  /// The service is stopping.
  case serviceStopped
  /// The virtual controller did not start, with the reason.
  case activationFailed(String)

  /// The message that the client sees.
  var errorDescription: String? {
    switch self {
    case .unknownProfile(let profile): "Unknown virtual HID profile: \(profile)."
    case .tooManyFeeds(let limit): "The service already runs \(limit) virtual feeds."
    case .serviceStopped: "The service is stopping."
    case .activationFailed(let detail): "The virtual controller did not start: \(detail)."
    }
  }
}
