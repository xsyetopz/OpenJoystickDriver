import Foundation

/// Owns the current virtual state and the exact report exposed through both push and get-report
/// APIs.
final class UserSpaceInputReportState: @unchecked Sendable {
  let hostSession: VirtualHostProtocolSession
  private let format: any VirtualGamepadReportFormat
  private let lock = NSLock()
  private var state = VirtualGamepadState()
  private var report: [UInt8]
  private var remapped = false
  private var pendingNintendoMotion: [RemappingVirtualMotionState] = []

  var isRemapped: Bool { lock.withLock { remapped } }
  var supportsMotion: Bool { format.supportsMotion }

  init(format: any VirtualGamepadReportFormat) {
    self.hostSession = VirtualHostProtocolSession(format: format)
    self.format = format
    self.report = format.buildInputReport(from: VirtualGamepadState())
  }

  func update(remapped: Bool = false, _ body: (inout VirtualGamepadState) -> Void) -> [UInt8] {
    lock.withLock {
      self.remapped = remapped
      body(&state)
      report = format.buildInputReport(from: state)
      return report
    }
  }

  func currentReport() -> [UInt8] { lock.withLock { report } }

  func updateMotion(_ motion: RemappingVirtualMotionState?) -> [UInt8]? {
    lock.withLock {
      remapped = true
      if format is SwitchProUSBHIDReportFormat, let motion {
        pendingNintendoMotion.append(motion)
        guard pendingNintendoMotion.count == 3 else { return nil }
        state.motionSamples = pendingNintendoMotion
        state.motion = pendingNintendoMotion.last
        let delta = pendingNintendoMotion.reduce(UInt64(0)) { total, sample in
          let (sum, overflow) = total.addingReportingOverflow(sample.deltaNanoseconds)
          return overflow ? .max : sum
        }
        advanceMotionClock(by: delta)
        pendingNintendoMotion.removeAll(keepingCapacity: true)
      } else {
        pendingNintendoMotion.removeAll(keepingCapacity: true)
        state.motionSamples.removeAll(keepingCapacity: true)
        if let motion { advanceMotionClock(by: motion.deltaNanoseconds) }
        state.motion = motion
      }
      report = format.buildInputReport(from: state)
      return report
    }
  }

  private func advanceMotionClock(by delta: UInt64) {
    let (timestamp, overflow) = state.motionTimestampNanoseconds.addingReportingOverflow(delta)
    state.motionTimestampNanoseconds = overflow ? .max : timestamp
  }
}
