import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverCLI

/// A profile library that answers the remapping requests as the service does, for `FakeService`.
final class FakeProfileLibrary: @unchecked Sendable {
  private let lock = NSLock()
  private var profiles: [RemappingProfile]
  private var active: Set<UUID>
  private var pairs: [ApplicationServiceJoyConPairPayload] = []
  private var issues: [ApplicationServiceRemappingProfileIssue]
  private let connected: [ApplicationServiceDeviceDescription]

  /// `connected` devices get a route to the active profile of their model, as the service reports.
  init(
    _ profiles: [RemappingProfile],
    active: Set<UUID> = [],
    connected: [ApplicationServiceDeviceDescription] = [],
    issues: [ApplicationServiceRemappingProfileIssue] = []
  ) {
    self.profiles = profiles
    self.active = active
    self.issues = issues
    self.connected = connected
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
      let activeProfiles = profiles.filter { active.contains($0.id) }.map {
        ApplicationServiceRemappingActiveProfilePayload(
          vendorID: $0.device.vendorID,
          productID: $0.device.productID,
          profileID: $0.id,
          profileName: $0.name,
          applicationScope: $0.applicationScope
        )
      }
      let routes = connected.map { device in
        let profile = activeProfiles.routingActiveProfile(
          vendorID: device.vendorID,
          productID: device.productID
        )
        return ApplicationServiceRemappingRoutePayload(
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier,
          selection: profile == nil ? .unavailable : .remapping,
          eligibility: profile == nil ? .unavailable : .eligible,
          activeProfileID: profile?.profileID,
          activeProfileName: profile?.profileName,
          applicationScope: profile?.applicationScope,
          frontmostBundleIdentifier: nil,
          postEventAccess: .granted,
          failure: nil
        )
      }
      return ApplicationServiceRemappingSnapshotPayload(
        profiles: profiles,
        activeProfiles: activeProfiles,
        routes: routes,
        joyConPairs: pairs,
        profileIssues: issues,
        postEventAccess: .granted
      )
    }
  }

  var stored: [RemappingProfile] { lock.withLock { profiles } }

  var storedIssues: [ApplicationServiceRemappingProfileIssue] { lock.withLock { issues } }

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
      case .activateRemappingProfile:
        guard
          let request = try? decoder.decode(
            ApplicationServiceRemappingActivateArguments.self,
            from: arguments
          )
        else { return nil }
        let activated = lock.withLock {
          guard let profile = profiles.first(where: { $0.id == request.profileID }),
            request.allowEmpty || !profile.producesNoOutput
          else { return false }
          active.insert(profile.id)
          return true
        }
        guard activated else { return nil }
      case .deleteRemappingProfile, .deactivateRemappingProfileByID:
        guard
          let id = try? decoder.decode(
            ApplicationServiceRemappingProfileIDArguments.self,
            from: arguments
          ).profileID
        else { return nil }
        lock.withLock {
          switch method {
          case .deleteRemappingProfile: profiles.removeAll { $0.id == id }
          default: active.remove(id)
          }
        }
      case .deleteDamagedRemappingProfile, .resetRemappingProfileLibrary:
        guard
          let id = try? decoder.decode(
            ApplicationServiceRemappingProfileIssueArguments.self,
            from: arguments
          ).issueID
        else { return nil }
        let kind: ApplicationServiceRemappingProfileIssue.Kind =
          method == .deleteDamagedRemappingProfile ? .damagedProfile : .unusableLibrary
        let removed = lock.withLock {
          let count = issues.count
          issues.removeAll { $0.id == id && $0.kind == kind }
          return issues.count < count
        }
        guard removed else { return nil }
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
