import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// Pins what each registry-built protocol driver decodes from input today, so replacing the delta
/// `[InputChange]` model with full state snapshots can be audited line by line.
///
/// Each step feeds one report (or, for `HIDDescriptorDriver`, one element value) at a fixed receipt
/// time and renders the snapshot it returns; a frame without input, or a report that threw, leaves
/// the previous snapshot in place:
/// - Pressed controls are `Control` names in declaration order.
/// - The hat renders as a `HatDirection` kebab name.
/// - Sticks render as their `BipolarValue` and triggers as their `UnipolarValue`. Y is rendered
///   down-positive (the canonical Y negated), the frame S1 pinned each driver's output in.
/// - `motion=`/`touch=` count the samples one step emitted; each sample follows on its own line.
///   Motion renders angular velocity `w=` in rad/s and acceleration `a=` in m/s², both in the
///   canonical frame, at four decimals so one count of the finest sensor scale stays visible.
/// - `fresh`/`stale` renders the latest input's freshness, only for a driver with a liveness
///   timeout.
/// - Battery renders in today's percentage-and-range form, on its own line whenever it changes.
/// - A step whose parse throws renders `threw=<error>` and the state it leaves behind.
struct DriverParseCharacterizationTests {
  static let receivedAt: UInt64 = 1_000_000_000

  enum Input {
    case report(Data)
    case element(HIDElementValue)
  }

  struct Step {
    let label: String
    let input: Input

    init(_ label: String, _ bytes: [UInt8]) {
      self.label = label
      input = .report(Data(bytes))
    }

    init(_ label: String, _ data: Data) {
      self.label = label
      input = .report(data)
    }

    init(_ label: String, element: HIDElementValue) {
      self.label = label
      input = .element(element)
    }
  }

  /// Builds the subject's driver the way discovery does: classify, then `makeDriver`.
  func driver(
    _ subject: DriverLifecycleCharacterizationTests.Subject
  ) throws -> any PhysicalProtocolDriver {
    try catalogParser(
      subject.model,
      host: subject.host,
      registry: DriverLifecycleCharacterizationTests.registry
    )
  }

  func transcript(
    _ subject: DriverLifecycleCharacterizationTests.Subject,
    _ steps: [Step]
  ) throws -> [String] {
    transcript(
      try driver(subject),
      steps
    )
  }

  func transcript(
    _ driver: any PhysicalProtocolDriver,
    _ steps: [Step]
  ) -> [String] {
    let receivedAt = MonotonicTimestamp(nanoseconds: Self.receivedAt)
    let rendersFreshness = driver.sessionPlan.inputReportLivenessTimeoutNanoseconds != nil
    var state = ControllerState.neutral
    var isFresh: Bool?
    var battery: String?
    var lines: [String] = []
    for step in steps {
      var event: ControllerEvent?
      var failure: String?
      switch step.input {
      case .report(let data):
        do { event = try driver.parse(report: data, receivedAt: receivedAt) } catch {
          failure = "\(error)"
        }
      case .element(let value): event = driver.parse(elementValue: value, receivedAt: receivedAt)
      }
      // A frame without input, or a report that threw, leaves the last state in place.
      if let event {
        state = event.state
        isFresh = event.isFresh
      }
      let motion = event?.motion ?? []
      let touch = event?.touchFrames ?? []
      var line = "\(step.label) \(render(state))"
      if !motion.isEmpty || !touch.isEmpty {
        line += " motion=\(motion.count) touch=\(touch.count)"
      }
      if rendersFreshness, let isFresh { line += isFresh ? " fresh" : " stale" }
      if let failure { line += " threw=\(failure)" }
      lines.append(line)
      lines += motion.map(render) + touch.map(render)
      let nextBattery = driver.power.map(render)
      if nextBattery != battery, let nextBattery { lines.append("  battery \(nextBattery)") }
      battery = nextBattery
    }
    return lines
  }

  // MARK: - Rendering

  /// Pressed controls in `Control` order; stick Y rendered down-positive, as S1 pinned it.
  func render(_ state: ControllerState) -> String {
    let pressed = Control.allCases.filter(state.pressed.contains).map(\.rawValue)
    return "[\(pressed.joined(separator: ","))] hat=\(state.hat.rawValue)"
      + " ls=\(state.leftStick.x.rawValue),\(state.leftStick.y.rawValue)"
      + " rs=\(state.rightStick.x.rawValue),\(state.rightStick.y.rawValue)"
      + " lt=\(state.leftTrigger.rawValue) rt=\(state.rightTrigger.rawValue)"
  }

  func render(_ sample: ControllerMotionSample) -> String {
    let rate = sample.angularVelocity
    let accel = sample.acceleration
    return "  motion n=\(sample.timestamp.rawCounter)"
      + " w=\(fixed(rate.x)),\(fixed(rate.y)),\(fixed(rate.z))"
      + " a=\(fixed(accel.x)),\(fixed(accel.y)),\(fixed(accel.z))"
  }

  /// Rounds before formatting so a tiny negative value cannot render as `-0.0000`.
  private func fixed(_ value: Double) -> String {
    unsafe String(format: "%.4f", (value * 10_000).rounded() / 10_000 + 0.0)
  }

  /// Contacts render as `slot:active:x,y`, plus `:pressure` when the contact reports one.
  func render(_ sample: ControllerTouchSample) -> String {
    let contacts = sample.contacts.map { contact in
      "\(contact.slot):\(contact.isActive ? 1 : 0):\(contact.x),\(contact.y)"
        + (contact.pressure.map { ":\($0.rawValue)" } ?? "")
    }
    return "  touch \(sample.surface.rawValue) [\(contacts.joined(separator: " "))]"
  }

  func render(_ power: ControllerConnectionState.Power) -> String {
    let range = power.battery.percentage
    let battery =
      range.map { $0.count == 1 ? "\($0.lowerBound)%" : "\($0.lowerBound)-\($0.upperBound)%" }
      ?? "unknown"
    let wired = power.wiredPower.map { $0 ? "yes" : "no" } ?? "unknown"
    return "\(battery) \(power.charging.rawValue) wired-power=\(wired)"
  }

  // MARK: - Step builders

  /// One step per set bit of `mask` at each offset, each bit ORed alone onto `base`.
  static func bitSteps(_ base: [UInt8], _ masks: [(offset: Int, mask: UInt8)]) -> [Step] {
    masks.flatMap { offset, mask in
      (0..<8).filter { mask & (1 << $0) != 0 }.map { bit in
        var report = base
        report[offset] |= 1 << bit
        return Step("b\(offset).\(bit)", report)
      }
    }
  }

  /// One step per value of the byte at `offset`, keeping the bits outside `mask` from `base`.
  static func valueSteps(
    _ base: [UInt8],
    offset: Int,
    mask: UInt8 = 0xFF,
    prefix: String,
    _ values: [UInt8]
  ) -> [Step] {
    values.map { value in
      var report = base
      report[offset] = (report[offset] & ~mask) | (value & mask)
      return Step("\(prefix)\(String(value, radix: 16))", report)
    }
  }

  /// Little-endian 16-bit values at `offset`, one step each.
  static func wordSteps(_ base: [UInt8], offset: Int, prefix: String, _ values: [UInt16]) -> [Step]
  {
    values.map { value in
      var report = base
      report[offset] = UInt8(truncatingIfNeeded: value)
      report[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
      return Step("\(prefix)\(String(value, radix: 16))", report)
    }
  }

  /// Rewrites each report step through `frame`, given its position, e.g. to wrap a payload in a
  /// transport header, advance a sensor timestamp, or append a CRC.
  static func framed(_ steps: [Step], _ frame: (Int, [UInt8]) -> [UInt8]) -> [Step] {
    steps.enumerated().map { index, step in
      guard case .report(let data) = step.input else { return step }
      return Step(step.label, frame(index, Array(data)))
    }
  }

  /// Signed 16-bit stick extremes, then centre: `Int16.min`, `-Int16.max`, `Int16.max`, 0.
  ///
  /// Ending on centre returns the report to neutral, so a following repeat of the base is
  /// identical.
  static let signedWordExtremes: [UInt16] = [0x8000, 0x8001, 0x7FFF, 0]
  /// Unsigned byte extremes and centres around 0x80: 0, 0x7F, 0x80, 0x81, 0xFF.
  static let byteExtremes: [UInt8] = [0x00, 0x7F, 0x80, 0x81, 0xFF]
}
