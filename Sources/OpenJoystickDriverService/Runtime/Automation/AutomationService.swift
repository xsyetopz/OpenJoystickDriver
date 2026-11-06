import Foundation
import OpenJoystickDriverKit

/// The service state that the app's Shortcuts actions read, called in the app's own process.
///
/// `ApplicationServiceServer` implements it without the RPC socket.
package protocol AutomationService: Sendable {
  /// The controllers that the service drives.
  func connectedDevices() async -> [ApplicationServiceDeviceDescription]
  /// Returns the snapshot of the remapping profiles, routes and issues.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the snapshot fails.
  func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Activates the profile `id`; `allowEmpty` lets a profile that produces no output activate.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the activation fails.
  func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Deactivates the profile `id`.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the deactivation fails.
  func deactivateRemappingProfile(
    id: UUID
  ) async throws
    -> ApplicationServiceRemappingSnapshotPayload
}

/// A connected controller as Shortcuts shows it.
package struct AutomationController: Equatable, Sendable {
  /// The port key, which lasts while the controller stays on the same port, or the session token
  /// when the controller has no port key; for a match by model, the `VVVV:PPPP` text itself.
  package let id: String
  /// The controller's name.
  package let name: String
  /// `VVVV:PPPP`, the vendor and product ID as `ojd` prints them.
  package let model: String
  /// Whether `id` names the model, so the entry stands for any one connected controller of it.
  package let isModelMatch: Bool
  /// The charge in percent as the controller reports it; `nil` when it reports no level.
  package let battery: ClosedRange<UInt8>?

  /// Creates the entry of a connected controller.
  package init(_ device: ApplicationServiceDeviceDescription) {
    id = device.portKey?.rawValue ?? device.sessionToken.rawValue
    name = device.name
    model = automationModel(vendorID: device.vendorID, productID: device.productID)
    isModelMatch = false
    battery = device.connectionState?.power.battery.percentage
  }

  /// The entry that `model` names, which resolves to `device`.
  package init(model: String, device: ApplicationServiceDeviceDescription) {
    id = model
    name = device.name
    self.model = automationModel(vendorID: device.vendorID, productID: device.productID)
    isModelMatch = true
    battery = device.connectionState?.power.battery.percentage
  }
}

/// A controller model in a Shortcuts action matches more than one connected controller.
package struct AutomationAmbiguousModelError: Error, Equatable, LocalizedError, Sendable {
  /// The `VVVV:PPPP` text that matched several controllers.
  package let model: String
  /// The controllers that the model matched.
  package let controllers: [AutomationController]

  /// The message that names the model and lists the controllers.
  package var errorDescription: String? {
    let message = Localization().plural(
      "cli.controller.group.selectorAmbiguous",
      arguments: [model, controllers.count]
    )
    return ([message] + controllers.map { "  \($0.id)  \($0.name)" }).joined(separator: "\n")
  }
}

/// Returns the `VVVV:PPPP` text of the vendor and product ID.
private func automationModel(vendorID: UInt16, productID: UInt16) -> String {
  String(format: "%04X:%04X", vendorID, productID)
}

/// A saved remapping profile as Shortcuts shows it.
package struct AutomationProfile: Equatable, Sendable {
  /// The profile's identity.
  package let id: UUID
  /// The profile's name.
  package let name: String
  /// `VVVV:PPPP` of the controller model that the profile applies to.
  package let model: String
  /// Whether the profile is active.
  package let isActive: Bool

  /// Creates the entry of `profile`, active when `snapshot` lists it as active.
  package init(_ profile: RemappingProfile, snapshot: ApplicationServiceRemappingSnapshotPayload) {
    id = profile.id
    name = profile.name
    model = automationModel(vendorID: profile.device.vendorID, productID: profile.device.productID)
    isActive = snapshot.activeProfiles.contains { $0.profileID == profile.id }
  }
}

extension AutomationService {
  /// Each connected controller, then one model entry for each connected model.
  package func controllers() async -> [AutomationController] {
    let devices = await connectedDevices()
    var models: [String: AutomationController] = [:]
    var modelOrder: [String] = []
    for device in devices {
      let model = automationModel(vendorID: device.vendorID, productID: device.productID)
      guard models[model] == nil else { continue }
      models[model] = AutomationController(model: model, device: device)
      modelOrder.append(model)
    }
    return devices.map(AutomationController.init) + modelOrder.compactMap { models[$0] }
  }

  /// The connected controllers that `ids` name, in the order of `ids`.
  ///
  /// Each ID is a ``ControllerReference``: a port key, a session token, or a `VVVV:PPPP` model,
  /// which matches the one connected controller of that model, as in `ojd`. IDs that match no
  /// connected controller are left out.
  ///
  /// - Throws: ``AutomationAmbiguousModelError`` when a model matches several controllers.
  package func controllers(ids: [String]) async throws -> [AutomationController] {
    let devices = await connectedDevices()
    return try ids.compactMap { id in
      guard let reference = ControllerReference(id) else { return nil }
      let matches = reference.matches(in: devices)
      guard case .model = reference else { return matches.first.map(AutomationController.init) }
      guard matches.count <= 1 else {
        throw AutomationAmbiguousModelError(
          model: id,
          controllers: matches.map(AutomationController.init)
        )
      }
      return matches.first.map { AutomationController(model: id, device: $0) }
    }
  }

  /// Returns every saved profile.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the snapshot fails.
  package func profiles() async throws -> [AutomationProfile] {
    let snapshot = try await getRemappingSnapshot()
    return snapshot.profiles.map { AutomationProfile($0, snapshot: snapshot) }
  }

  /// The saved profiles that `ids` name, in the order of `ids`; unknown IDs are left out.
  package func profiles(ids: [UUID]) async throws -> [AutomationProfile] {
    let snapshot = try await getRemappingSnapshot()
    return ids.compactMap { id in
      snapshot.profiles.first { $0.id == id }.map { AutomationProfile($0, snapshot: snapshot) }
    }
  }

  /// Activates the profile with `id` and returns it as the service reports it afterward.
  ///
  /// Shortcuts cannot confirm, so a profile that produces no output is refused.
  package func activateProfile(id: UUID) async throws -> AutomationProfile {
    try Self.profile(id: id, in: try await activateRemappingProfile(id: id, allowEmpty: false))
  }

  /// Deactivates the profile with `id` and returns it as the service reports it afterward.
  package func deactivateProfile(id: UUID) async throws -> AutomationProfile {
    try Self.profile(id: id, in: try await deactivateRemappingProfile(id: id))
  }

  /// Returns the entry of the profile `id` in `snapshot`.
  ///
  /// - Throws: ``RemappingProfileLibraryError/profileNotFound(_:)`` when the snapshot lacks it.
  private static func profile(
    id: UUID,
    in snapshot: ApplicationServiceRemappingSnapshotPayload
  ) throws -> AutomationProfile {
    guard let profile = snapshot.profiles.first(where: { $0.id == id }) else {
      throw RemappingProfileLibraryError.profileNotFound(id)
    }
    return AutomationProfile(profile, snapshot: snapshot)
  }
}
