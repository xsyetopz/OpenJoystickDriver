import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverCLI

/// A profile library that answers the remapping requests as the service does, for `FakeService`.
final class FakeProfileLibrary: @unchecked Sendable {
  private let lock = NSLock()
  private var profiles: [RemappingProfile]
  private var active: Set<UUID>
  private var pairs: [ApplicationServiceJoyConPairPayload] = []

  init(_ profiles: [RemappingProfile], active: Set<UUID> = []) {
    self.profiles = profiles
    self.active = active
  }

  static func profile(
    _ name: String,
    id: UUID = UUID(),
    virtualGamepad: RemappingVirtualGamepadPolicy = .passthrough,
    bindings: [RemappingBinding] = []
  ) -> RemappingProfile {
    RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: 0x045E, productID: 0x028E),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: virtualGamepad),
      bindings: bindings
    )
  }

  var snapshot: ApplicationServiceRemappingSnapshotPayload {
    lock.withLock {
      ApplicationServiceRemappingSnapshotPayload(
        profiles: profiles,
        activeProfiles: profiles.filter { active.contains($0.id) }.map {
          ApplicationServiceRemappingActiveProfilePayload(
            vendorID: $0.device.vendorID,
            productID: $0.device.productID,
            profileID: $0.id,
            profileName: $0.name,
            applicationScope: $0.applicationScope
          )
        },
        routes: [],
        joyConPairs: pairs,
        postEventAccess: .granted
      )
    }
  }

  var stored: [RemappingProfile] { lock.withLock { profiles } }

  var respond: FakeService.Respond {
    { [self] method, arguments in
      let decoder = JSONDecoder()
      switch method {
      case .getRemappingSnapshot: break
      case .createRemappingProfile, .importRemappingProfile:
        guard
          let profile = try? decoder.decode(
            ApplicationServiceRemappingProfileArguments.self,
            from: arguments
          ).profile
        else { return nil }
        lock.withLock {
          profiles.removeAll { $0.id == profile.id }
          profiles.append(profile)
        }
      case .updateRemappingProfile:
        guard
          let update = try? decoder.decode(
            ApplicationServiceRemappingProfileUpdateArguments.self,
            from: arguments
          )
        else { return nil }
        lock.withLock {
          profiles = profiles.map { $0.id == update.profile.id ? update.profile : $0 }
        }
      case .deleteRemappingProfile, .activateRemappingProfile, .deactivateRemappingProfileByID:
        guard
          let id = try? decoder.decode(
            ApplicationServiceRemappingProfileIDArguments.self,
            from: arguments
          ).profileID
        else { return nil }
        lock.withLock {
          switch method {
          case .deleteRemappingProfile: profiles.removeAll { $0.id == id }
          case .activateRemappingProfile: active.insert(id)
          default: active.remove(id)
          }
        }
      case .pairRemappingJoyCons:
        guard
          let pair = try? decoder.decode(
            ApplicationServiceJoyConPairArguments.self,
            from: arguments
          )
        else { return nil }
        lock.withLock {
          pairs.append(
            ApplicationServiceJoyConPairPayload(
              sessionID: UUID(),
              leftRuntimeIdentifier: pair.leftRuntimeIdentifier,
              rightRuntimeIdentifier: pair.rightRuntimeIdentifier,
              profileID: pair.profileID,
              profileName: profiles.first { $0.id == pair.profileID }?.name ?? "",
              gyroSelection: .left
            )
          )
        }
      case .unpairRemappingJoyCons:
        guard
          let unpair = try? decoder.decode(
            ApplicationServiceJoyConUnpairArguments.self,
            from: arguments
          )
        else { return nil }
        lock.withLock { pairs.removeAll { $0.sessionID == unpair.sessionID } }
      default: return nil
      }
      return encoded(snapshot)
    }
  }
}
