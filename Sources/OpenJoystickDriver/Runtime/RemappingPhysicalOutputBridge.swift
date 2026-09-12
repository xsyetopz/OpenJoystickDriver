import Foundation
import OpenJoystickDriverKit

final class RemappingPhysicalOutputBridge: RemappingPhysicalOutputSink, @unchecked Sendable {
  private weak var manager: DeviceManager?
  private let lock = NSLock()

  func attach(_ manager: DeviceManager) {
    lock.withLock { self.manager = manager }
  }

  func set(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: DeviceIdentifier
  ) async throws {
    guard let manager = lock.withLock({ manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    guard await manager.setMappingPhysicalOutput(
      output,
      active: active,
      owner: owner,
      for: identifier
    ) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }

  func releaseAll(for identifier: DeviceIdentifier) async throws {
    guard let manager = lock.withLock({ manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    guard await manager.releaseMappingPhysicalOutputs(for: identifier) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }
}
