import Foundation
import OpenJoystickDriverKit

/// Carries the physical outputs of a remapping profile to the device manager.
final class RemappingPhysicalOutputBridge: RemappingPhysicalOutputSink, Sendable {
  /// A weak reference to the device manager.
  private struct WeakManager {
    /// The device manager that receives the outputs.
    weak var manager: DeviceManager?
  }

  /// The device manager, once attached.
  private let attached = Locked(WeakManager())

  /// Attaches the device manager that receives the outputs.
  func attach(_ manager: DeviceManager) { attached.withLock { $0.manager = manager } }

  /// Sets whether `owner` holds `output` on the controller.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when no manager is attached or the
  ///   manager refuses.
  func set(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: LogicalControllerID
  ) async throws {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    do {
      try await manager.consume(
        MappingOutputClaim(output, active: active, owner: owner),
        for: identifier
      )
    } catch { throw RemappingEventEngineError.sinkUnavailable }
  }

  /// Releases every output that a profile holds on the controller.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when no manager is attached or the
  ///   manager refuses.
  func releaseAll(for identifier: LogicalControllerID) async throws {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    do { try await manager.consume(MappingOutputRelease(), for: identifier) } catch {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }

  /// Sets the color that the profile gives the controller, or removes it when nil.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when no manager is attached or the
  ///   manager refuses.
  func setProfileColor(_ color: ControllerColor?, for identifier: LogicalControllerID) async throws
  {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    do { try await manager.consume(ProfileColorClaim(color), for: identifier) } catch {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }
}
