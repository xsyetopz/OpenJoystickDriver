import Foundation
import OpenJoystickDriverKit

/// The service state that the app's Shortcuts actions read, called in the app's own process.
///
/// `ApplicationServiceServer` implements it without the RPC socket.
package protocol AutomationService: Sendable {
  /// The controllers that the service drives now.
  func connectedDevices() async -> [ApplicationServiceDeviceDescription]
  func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload
}

/// A connected controller as Shortcuts shows it.
package struct AutomationController: Equatable, Sendable {
  /// The unit ID, which lasts while the controller stays on the same port, or the runtime ID
  /// when the controller reports no unit ID; for a match by model, the `VVVV:PPPP` text itself.
  package let id: String
  package let name: String
  /// `VVVV:PPPP`, the vendor and product ID as `ojd` prints them.
  package let model: String
  /// Whether `id` names the model, so the entry stands for any one connected controller of it.
  package let isModelMatch: Bool

  package init(_ device: ApplicationServiceDeviceDescription) {
    id = device.unitIdentifier ?? device.runtimeIdentifier
    name = device.name
    model = automationModel(vendorID: device.vendorID, productID: device.productID)
    isModelMatch = false
  }

  /// The entry that `model` names, which resolves to `device`.
  package init(model: String, device: ApplicationServiceDeviceDescription) {
    id = model
    name = device.name
    self.model = automationModel(vendorID: device.vendorID, productID: device.productID)
    isModelMatch = true
  }
}

/// A controller model in a Shortcuts action matches more than one connected controller.
package struct AutomationAmbiguousModelError: Error, Equatable, LocalizedError, Sendable {
  package let model: String
  package let controllers: [AutomationController]

  package var errorDescription: String? {
    let message = Localization().formatted(
      "cli.controller.selector.ambiguous",
      defaultValue: "'%@' matches %lld controllers. Use one of these IDs:",
      arguments: [model, controllers.count]
    )
    return ([message] + controllers.map { "  \($0.id)  \($0.name)" }).joined(separator: "\n")
  }
}

/// `VVVV:PPPP`, four hex digits each, case-insensitive.
package func parseControllerModel(_ text: String) -> (vendorID: UInt16, productID: UInt16)? {
  let parts = text.split(separator: ":", omittingEmptySubsequences: false)
  guard parts.count == 2, parts.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isHexDigit) }),
    let vendorID = UInt16(parts[0], radix: 16), let productID = UInt16(parts[1], radix: 16)
  else { return nil }
  return (vendorID, productID)
}

private func automationModel(vendorID: UInt16, productID: UInt16) -> String {
  String(format: "%04X:%04X", vendorID, productID)
}

/// A saved remapping profile as Shortcuts shows it.
package struct AutomationProfile: Equatable, Sendable {
  package let id: UUID
  package let name: String
  /// `VVVV:PPPP` of the controller model that the profile applies to.
  package let model: String
  package let isActive: Bool

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
  /// An ID matches a unit ID or a runtime ID, so an ID saved before the controller had a unit ID
  /// still resolves. An ID in the form `VVVV:PPPP` matches the one connected controller of that
  /// model, as in `ojd`. IDs that match no connected controller are left out.
  ///
  /// - Throws: ``AutomationAmbiguousModelError`` when a model matches several controllers.
  package func controllers(ids: [String]) async throws -> [AutomationController] {
    let devices = await connectedDevices()
    return try ids.compactMap { id in
      let byID = devices.first { $0.unitIdentifier == id || $0.runtimeIdentifier == id }
      if let device = byID { return AutomationController(device) }
      guard let (vendorID, productID) = parseControllerModel(id) else { return nil }
      let matches = devices.filter { $0.vendorID == vendorID && $0.productID == productID }
      guard matches.count <= 1 else {
        throw AutomationAmbiguousModelError(
          model: id,
          controllers: matches.map(AutomationController.init)
        )
      }
      return matches.first.map { AutomationController(model: id, device: $0) }
    }
  }

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
}
