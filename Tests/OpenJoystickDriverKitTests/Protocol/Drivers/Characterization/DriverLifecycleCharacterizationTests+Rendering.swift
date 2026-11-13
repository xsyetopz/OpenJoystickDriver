import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Output encoder rendering shared by every transcript.
extension DriverLifecycleCharacterizationTests {
  // MARK: - Output encoders

  /// The representative rumble request: main, trigger and haptic motors all set.
  static let rumbleIntensities: [PhysicalRumbleMotor: UInt8] = [
    .lowFrequency: 0x40, .highFrequency: 0x80, .leftTrigger: 0x20, .rightTrigger: 0x10,
    .leftHaptic: 0x40,
    .rightHaptic: 0x80,
  ]
  static let triggerResistance = PhysicalAdaptiveTriggerEffect(
    kind: .resistance,
    startPosition: 0.25,
    strength: 0.75
  )

  /// Encoder results for a fixed representative request; nil results render no line.
  ///
  /// Each encoder runs once per stage, since encoders may advance protocol state.
  func outputs(_ driver: any PhysicalProtocolDriver, stage: String) -> [String] {
    let prefix = "out[\(stage)]"
    var lines = rumbleOutputs(driver, prefix: prefix)
    lines += colorOutputs(driver, prefix: prefix)
    lines += brightnessOutputs(driver, prefix: prefix)
    lines += playerIndicatorOutputs(driver, prefix: prefix)
    if let left = driver.encoded(.setAdaptiveTrigger(.left, Self.triggerResistance)) {
      lines += ["\(prefix).trigger[Left] resistance(0.25,0.75)"] + left.writes.flatMap(render)
    }
    if let right = driver.encoded(.setAdaptiveTrigger(.right, .off)) {
      lines += ["\(prefix).trigger[Right] off"] + right.writes.flatMap(render)
    }
    return lines
  }

  /// Labeled by destination: USB packets, HID output reports, or feature-report haptics.
  func rumbleOutputs(_ driver: any PhysicalProtocolDriver, prefix: String) -> [String] {
    guard
      let plan = driver.encoded(
        .setRumble(RumbleIntensities(bytes: Self.rumbleIntensities), duration: .milliseconds(100))
      )
    else { return [] }
    let caps = driver.outputCapabilities
    // Declaration order, matching how the drivers list their motors.
    let motors = names(PhysicalRumbleMotor.allCases.filter(caps.rumbleMotors.contains))
    switch plan.writes.first {
    case .usb: return ["\(prefix).usbRumble motors=\(motors)"] + plan.writes.flatMap(render)
    case .hidOutput:
      return [
        "\(prefix).hidRumble motors=\(motors) binary=\(names(caps.binaryRumbleMotors))"
          + " minInterval=\(driver.sessionPlan.minimumHIDOutputIntervalNanoseconds)"
      ] + plan.writes.flatMap(render)
    case .hidFeature, nil:
      return [
        "\(prefix).haptics motors=\(motors)", "\(prefix).haptics reports=\(plan.writes.count)",
      ] + plan.writes.flatMap(render)
    }
  }

  func colorOutputs(_ driver: any PhysicalProtocolDriver, prefix: String) -> [String] {
    guard let defaultColor = driver.defaultColor else { return [] }
    let plan = driver.encoded(.setRGB(ControllerColor(red: 0x11, green: 0x22, blue: 0x33)))
    let color = "\(defaultColor.red),\(defaultColor.green),\(defaultColor.blue)"
    return ["\(prefix).color default=\(color)"] + (plan.map(render) ?? ["\(prefix).color plan=nil"])
  }

  /// A feature-report encoder renders its report; any other renders its HID output plan and its
  /// USB packets, nil where the bound variant produces none.
  func brightnessOutputs(_ driver: any PhysicalProtocolDriver, prefix: String) -> [String] {
    guard driver.outputCapabilities.supportsProgrammableBrightness else { return [] }
    let plan = driver.encoded(.setLightBrightness(UnipolarValue(byte: 0x80)))
    if case .hidFeature = plan?.writes.first {
      return ["\(prefix).hidFeatureBrightness"] + (plan?.writes.flatMap(render) ?? [])
    }
    let hidPlan = plan.flatMap { $0.writes.hidOutputs.isEmpty ? nil : $0 }
    let packets = plan.flatMap { $0.writes.usbPackets.isEmpty ? nil : $0.writes.usbPackets }
    return ["\(prefix).hidBrightnessPlan"] + (hidPlan.map(render) ?? ["  plan=nil"]) + [
      "\(prefix).usbBrightness packets=\(packets.map { "\($0.count)" } ?? "nil")"
    ] + (packets ?? []).flatMap(render)
  }

  func playerIndicatorOutputs(_ driver: any PhysicalProtocolDriver, prefix: String) -> [String] {
    var lines: [String] = []
    for indicator in PhysicalPlayerIndicator.allCases {
      guard let plan = driver.encoded(.setPlayerIndicator(indicator)) else { continue }
      let label = if case .usb = plan.writes.first { "usbPlayer" } else { "hidPlayer" }
      lines += ["\(prefix).\(label)[\(indicator)]"] + plan.writes.flatMap(render)
    }
    return lines
  }

  func render(_ write: PhysicalOutputWrite) -> [String] {
    switch write {
    case .usb(let packet, _): render(packet)
    case .hidOutput(let report), .hidFeature(let report): render(report)
    }
  }
}
