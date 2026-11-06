import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Driver-level output requests beyond the representative request: all-zero rumble, channel
// subsets, cross-command ordering on one driver, Steam durations, and GameSir readiness gates.
extension DriverLifecycleCharacterizationTests {
  static let namedSubjects: [(String, Subject)] = [
    ("gipUSB", gipUSB), ("gipKeepAliveDisabled", gipKeepAliveDisabled), ("xidGamepad", xidGamepad),
    ("xusbWired", xusbWired), ("xusbReceiver", xusbReceiver), ("sixaxisUSB", sixaxisUSB),
    ("sixaxisBluetooth", sixaxisBluetooth), ("dualShock4USB", dualShock4USB),
    ("dualShock4Bluetooth", dualShock4Bluetooth), ("dualSenseUSB", dualSenseUSB),
    ("dualSenseBluetooth", dualSenseBluetooth), ("switchUSB", switchUSB),
    ("switchBluetooth", switchBluetooth), ("steamWired", steamWired), ("steamDongle", steamDongle),
    ("flydigi", flydigi), ("gameSirUSB", gameSirUSB), ("gameSirEnhancedHID", gameSirEnhancedHID),
    ("gameSirEnhancedHID8K", gameSirEnhancedHID8K), ("hidDescriptor", hidDescriptor),
  ]

  static let triggerRumbleOnly: [PhysicalRumbleMotor: UInt8] = [
    .leftTrigger: 0x20, .rightTrigger: 0x10,
  ]
  static let mainRumbleOnly: [PhysicalRumbleMotor: UInt8] = [
    .lowFrequency: 0x40, .highFrequency: 0x80,
  ]

  func rumbleLines(
    _ driver: any PhysicalProtocolDriver,
    _ intensities: [PhysicalRumbleMotor: UInt8],
    durationMs: Int,
    label: String
  ) -> [String] {
    [label]
      + (driver.encoded(
        .setRumble(RumbleIntensities(bytes: intensities), duration: .milliseconds(durationMs))
      ).map(render) ?? ["  nil"])
  }

  /// Stop on a readied driver for every subject that encodes rumble; stop encodes exactly what an
  /// all-zero rumble at 0 ms encodes.
  func zeroRumbleLines(_ subjects: ArraySlice<(String, Subject)>) throws -> [String] {
    try subjects.flatMap { name, subject -> [String] in
      let driver = try driver(subject)
      feed(driver, subject.readyingInput)
      guard let zero = driver.encoded(.setRumble(.off, duration: .milliseconds(0))) else {
        return []
      }
      let fresh = try self.driver(subject)
      feed(fresh, subject.readyingInput)
      let stop = fresh.encoded(.stopRumble)
      #expect(stop == zero, "\(name): stop differs from all-zero rumble")
      let advertised = names(fresh.outputCapabilities.rumbleMotors)
      return ["\(name) off \(advertised)"] + (stop.map(render) ?? ["  nil"])
    }
  }

  /// GIP trigger-only and main-only requests, each on a fresh driver so both start at the same
  /// sequence number.
  func gipChannelSubsetLines() throws -> [String] {
    rumbleLines(try driver(Self.gipUSB), Self.triggerRumbleOnly, durationMs: 100, label: "triggers")
      + rumbleLines(try driver(Self.gipUSB), Self.mainRumbleOnly, durationMs: 100, label: "main")
  }

  /// Trigger-only requests to DS4 and Switch, which have no trigger motors.
  func droppedTriggerChannelLines() throws -> [String] {
    let subjects = [
      ("dualShock4USB", Self.dualShock4USB), ("dualShock4Bluetooth", Self.dualShock4Bluetooth),
      ("switchUSB", Self.switchUSB), ("switchBluetooth", Self.switchBluetooth),
    ]
    return try subjects.flatMap { name, subject in
      rumbleLines(try driver(subject), Self.triggerRumbleOnly, durationMs: 100, label: name)
    }
  }

  /// The representative all-channel request to each Joy-Con side, bound through the catalog.
  func joyConSideLines() throws -> [String] {
    try [("left", Self.model(0x057E, 0x2006)), ("right", Self.model(0x057E, 0x2007))]
      .flatMap { side, model in
        let driver = try catalogParser(model, host: .bluetoothClassic, registry: Self.registry)
        let motors = names(driver.outputCapabilities.rumbleMotors)
        return rumbleLines(
          driver,
          Self.rumbleIntensities,
          durationMs: 100,
          label: "joyCon[\(side)] \(motors)"
        )
      }
  }

  func playerLines(
    _ driver: any PhysicalProtocolDriver,
    _ indicator: PhysicalPlayerIndicator
  ) -> [String] {
    ["player[\(indicator)]"]
      + (driver.encoded(.setPlayerIndicator(indicator)).map(render) ?? ["  nil"])
  }

  func colorLines(_ driver: any PhysicalProtocolDriver) -> [String] {
    ["color"]
      + (driver.encoded(.setRGB(ControllerColor(red: 0x11, green: 0x22, blue: 0x33))).map(render)
        ?? ["  nil"])
  }

  func brightnessLines(_ driver: any PhysicalProtocolDriver, _ value: UInt8) -> [String] {
    ["brightness[\(value)]"]
      + (driver.encoded(.setLightBrightness(UnipolarValue(byte: value))).map(render) ?? ["  nil"])
  }

  /// Rumble then player 2 on one driver.
  ///
  /// The Switch player subcommand embeds the last rumble data; the Sixaxis report 0x01 carries
  /// both.
  func rumbleThenPlayerLines(_ subject: Subject) throws -> [String] {
    let driver = try driver(subject)
    return rumbleLines(driver, Self.rumbleIntensities, durationMs: 100, label: "rumble")
      + playerLines(driver, .player2)
  }

  /// Rumble, colour, then player 2 on one Bluetooth driver; each report advances the sequence.
  func dualSenseBluetoothSequenceLines() throws -> [String] {
    let driver = try driver(Self.dualSenseBluetooth)
    return rumbleLines(driver, Self.rumbleIntensities, durationMs: 100, label: "rumble")
      + colorLines(driver) + playerLines(driver, .player2)
  }

  /// Two rumbles on one driver; each packet advances the GIP sequence number.
  func gipTwoRumbleLines() throws -> [String] {
    let driver = try driver(Self.gipUSB)
    return rumbleLines(driver, Self.rumbleIntensities, durationMs: 100, label: "first")
      + rumbleLines(driver, Self.mainRumbleOnly, durationMs: 100, label: "second")
  }

  /// Steam haptics at 0, 65 and 5000 ms once the dongle reports a controller, then with no
  /// logical controller, then on the wired controller at 0 ms.
  func steamDurationLines() throws -> [String] {
    var lines: [String] = []
    for durationMs in [0, 65, 5000] {
      let driver = try driver(Self.steamDongle)
      feed(driver, Self.steamDongle.readyingInput)
      lines += rumbleLines(
        driver,
        Self.rumbleIntensities,
        durationMs: durationMs,
        label: "dongle ms=\(durationMs)"
      )
    }
    lines += rumbleLines(
      try driver(Self.steamDongle),
      Self.rumbleIntensities,
      durationMs: 100,
      label: "dongle noController"
    )
    return lines
      + rumbleLines(
        try driver(Self.steamWired),
        Self.rumbleIntensities,
        durationMs: 0,
        label: "wired"
      )
  }

  /// Colour then brightness 0x80 on a fresh driver per readiness stage: no input, the slot reply
  /// alone, the session-readying report alone, and both.
  func gameSirReadinessLines(_ subject: Subject) throws -> [String] {
    let input = subject.readyingInput
    let stages: [(String, [Data])] = [
      ("cold", []), ("slotOnly", Array(input.prefix(1))), ("sessionOnly", Array(input.dropFirst())),
      ("ready", input),
    ]
    return try stages.flatMap { stage, data -> [String] in
      let driver = try driver(subject)
      feed(driver, data)
      return ["stage \(stage)"] + colorLines(driver) + brightnessLines(driver, 0x80)
    }
  }
}
