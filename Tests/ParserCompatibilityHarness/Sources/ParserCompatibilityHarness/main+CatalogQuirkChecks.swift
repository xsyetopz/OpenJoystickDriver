import Foundation
import OpenJoystickDriverKit

/// The USB DualShock 4 driver the registry binds for the catalog record of `productID`.
private func dualShock4Driver(vendorID: UInt16 = 0x054C, _ productID: UInt16) -> DualShock4Driver {
  let quirks = catalogRecord(DeviceIdentifier(vendorID: vendorID, productID: productID)).quirks
  return DualShock4Driver(
    usesFactoryCalibration: quirks.contains(.factoryCalibration),
    model: DualShock4Model(quirks: quirks)
  )
}

/// The SHIELD driver the registry binds for the catalog record of `productID`.
private func shieldDriver(_ productID: UInt16) -> NVIDIAShieldDriver {
  let quirks = catalogRecord(DeviceIdentifier(vendorID: 0x0955, productID: productID)).quirks
  return NVIDIAShieldDriver(isShield2015: quirks.contains(.shield2015))
}

/// A neutral 64-byte USB input report with raw gyro and accelerometer X, and SDL's no-pad flag.
private func ds4Report(gyroX: UInt8 = 0, accelX: UInt8 = 0, noPad: Bool = false) -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  for index in 1...4 { report[index] = 128 }
  report[5] = 0x08
  report[13] = gyroX
  report[19] = accelX
  if noPad { report[31] = 0x04 }
  return Data(report)
}

/// A USB calibration reply whose gyro endpoints are valid only in the Bluetooth order (all plus
/// endpoints, then all minus endpoints), which only the wireless adapter reads.
private func groupedGyroCalibration() -> Data {
  var report = [UInt8](repeating: 0, count: 37)
  report[0] = 0x02
  func put(_ value: Int16, at offset: Int) {
    let bits = UInt16(bitPattern: value)
    report[offset] = UInt8(truncatingIfNeeded: bits)
    report[offset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
  }
  let gyroPlus: [Int16] = [8_640, 0, 8_640]
  let gyroMinus: [Int16] = [-8_640, -17_280, -8_640]
  for index in 0..<3 {
    put(gyroPlus[index], at: 7 + index * 2)
    put(gyroMinus[index], at: 13 + index * 2)
    put(8_192, at: 23 + index * 4)
    put(-8_192, at: 25 + index * 4)
  }
  put(540, at: 19)
  put(540, at: 21)
  return Data(report)
}

/// The record quirks select SDL's DualShock 4 models and factory calibration by product.
func runDualShock4RecordQuirkChecks() throws {
  let request = PhysicalHIDFeatureReadRequest(reportID: 2, length: 37)
  let grouped = groupedGyroCalibration()
  for (productID, isAdapter) in [
    (UInt16(0x05C4), false), (0x05C5, false), (0x09CC, false), (0x0BA0, true),
  ] {
    let driver = dualShock4Driver(productID)
    require(
      driver.sessionPlan.requiresInputConnectionBeforeOutput == isAdapter,
      "Only the DS4 wireless adapter should wait for a pad before output (\(productID))"
    )
    require(
      driver.consumeFeatureReply(grouped, request: request) == isAdapter,
      "Only the DS4 wireless adapter should read USB calibration in the Bluetooth order"
    )
    let noPadState = try parse(driver, ds4Report(noPad: true))
    require(
      (noPadState == nil) == isAdapter,
      "Only the DS4 wireless adapter should drop no-pad reports (\(productID))"
    )
  }
  require(
    dualShock4Driver(vendorID: 0x0079, 0x181B).consumeFeatureReply(grouped, request: request),
    "A third-party DS4 should ignore its calibration report and keep the nominal scale"
  )

  let report = ds4Report(gyroX: 160, accelX: 160)
  let receivedAt = MonotonicTimestamp(nanoseconds: 0)
  let standard = try dualShock4Driver(0x09CC).parse(report: report, receivedAt: receivedAt)
  let strikePad = try dualShock4Driver(0x05C5).parse(report: report, receivedAt: receivedAt)
  guard let standard = standard?.motion.first, let strikePad = strikePad?.motion.first else {
    require(false, "DS4 USB reports should carry a motion sample")
    return
  }
  require(
    abs(strikePad.angularVelocity.x - 2 * standard.angularVelocity.x) < 1e-9
      && abs(strikePad.acceleration.x + 2 * standard.acceleration.x) < 1e-9,
    "The STRIKEPAD should double the gyro scale and negate the doubled accelerometer scale"
  )
}

/// Only the 2015 SHIELD record selects plain rumble and the touchpad click report.
func runShieldRecordQuirkChecks() throws {
  let shield2015 = shieldDriver(0x7210)
  let shield2017 = shieldDriver(0x7214)
  require(shield2015.outputCapabilities == .dualMainRumble, "SHIELD 2015 should rumble")
  require(shield2017.outputCapabilities == .none, "SHIELD 2017 should be input-only")
  let touch = Data([0x02, 0x01])
  let touch2015 = try parse(shield2015, touch)
  let touch2017 = try parse(shield2017, touch)
  require(
    touch2015?.pressed.contains(.touchpadClick) == true,
    "SHIELD 2015 should parse the touchpad click report"
  )
  require(touch2017 == nil, "SHIELD 2017 should ignore report 2")
}

/// The 11C1:5600 record carries the stick deadzone the output dispatcher applies.
func runStickDeadzoneTuningCheck() {
  require(
    catalogRecord(DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600)).tuning.stickDeadzone
      == 0.02,
    "11C1:5600 should tune a 0.02 stick deadzone"
  )
}
