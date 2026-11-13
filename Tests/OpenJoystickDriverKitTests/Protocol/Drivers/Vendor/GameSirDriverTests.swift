import Foundation
import OpenJoystickDriverKit
import Testing

struct GameSirDriverTests {
  static let family = PhysicalProtocolID.vendorGameSir
  static let model = ControllerModelID(vendorID: 0x3537, productID: 0x1003)

  @Test
  func enhancedReportMapsGameplayExtrasAndBatteryWithoutMotion() throws {
    let parser = GameSirDriver(protocol: .enhancedHID, hasInnerGrips: true)
    _ = try parser.parseReport(enhanced())
    let events = try parser.parseReport(
      enhanced(
        leftX: 255,
        leftY: 0,
        rightX: 0,
        rightY: 255,
        face: 0x20 | 1,
        meta: 0x01,
        leftTrigger: 255,
        rightTrigger: 128,
        counter: 1,
        extras: 0x08 | 0x10 | 0x20 | 0x40 | 0x80,
        battery: 84,
        charging: true
      ),
      at: 1_000
    )

    #expect(events.contains(.press(.south)))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.hat(.northEast)))
    #expect(events.contains(.leftStick(x: 1, y: 1)))
    #expect(events.contains(.rightStick(x: -1, y: -1)))
    #expect(events.contains(.leftTrigger(1)))
    #expect(events.contains(.press(.leftPaddle1)))
    #expect(events.contains(.press(.rightPaddle1)))
    #expect(events.contains(.press(.leftPaddle2)))
    #expect(events.contains(.press(.rightPaddle2)))
    #expect(events.contains(.press(.auxiliary1)))
    // No verified IMU scale or frame: the IMU bytes are not published as motion.
    #expect(events?.motion.isEmpty == true)
    #expect(!parser.capabilities.motion)
    #expect(parser.power?.battery == BatteryLevel(percentage: 84...84))
    #expect(parser.power?.charging == .charging)
    #expect(parser.power?.wiredPower == true)
  }

  @Test
  func enhancedReportsPublishNoMotionAndMalformedFramesPreserveState() throws {
    let parser = GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true)
    let pressed = enhanced(face: 0x20 | 7, counter: 9, extras: 0x08)
    let first = try parser.parseReport(pressed, at: 100)
    #expect(first.contains(.press(.south)))
    #expect(first.contains(.hat(.northWest)))
    #expect(first?.motion.isEmpty == true)
    #expect(try parser.parseReport(Data([0x12, 1, 2])) == nil)
    let repeated = try parser.parseReport(pressed, at: 200)
    #expect(repeated?.state == first?.state)
    #expect(repeated?.motion.isEmpty == true)
    let released = try parser.parseReport(enhanced(counter: 10))
    #expect(released.contains(.release(.south)))
    #expect(released.contains(.release(.leftPaddle1)))
    #expect(released.contains(.hat(.north)))
  }

  @Test
  func enhancedParametersSelectInnerGripsAndLightingSlotRequest() throws {
    let grips = GameSirDriver(protocol: .enhancedHID, hasInnerGrips: true)
    let slots = GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true)
    let innerGrips: Set<Control> = [.leftPaddle2, .rightPaddle2]
    #expect(innerGrips.isSubset(of: grips.capabilities.controls))
    #expect(innerGrips.isDisjoint(with: slots.capabilities.controls))
    let gripPress = enhanced(extras: 0x40 | 0x80)
    #expect(try grips.parseReport(gripPress).contains(.press(.leftPaddle2)))
    #expect(!(try slots.parseReport(gripPress).contains(.press(.leftPaddle2))))
    #expect(grips.startupWrites().isEmpty)
    #expect(slots.startupWrites().isEmpty)
  }

  @Test
  func g7UsesStandardXInputForGameplayAndVendorStreamForExtras() throws {
    let parser = GameSirDriver(protocol: .g7ProUSB)
    var standard = [UInt8](repeating: 0, count: 20)
    standard[1] = 0x14
    standard[2] = 0x01
    standard[3] = 0x10
    standard[4] = 255
    let gameplay = try parser.parseReport(Data(standard))
    #expect(gameplay.contains(.press(.south)))
    #expect(gameplay.contains(.hat(.north)))
    #expect(gameplay.contains(.leftTrigger(1)))

    var telemetry = [UInt8](repeating: 0, count: 64)
    telemetry[0] = 0x10
    telemetry[3] = 0x3C
    telemetry[4] = 0xE0
    telemetry[32] = 1
    telemetry[33] = 73
    telemetry[60] = 0x08 | 0x40
    let extras = try parser.parseReport(Data(telemetry))
    // Telemetry adds its extras to the standard stream's controls.
    #expect(extras?.state.pressed == [.south, .leftPaddle1, .leftPaddle2])
    #expect(parser.power?.battery == BatteryLevel(percentage: 73...73))
  }

  @Test
  func parserSpecificHeartbeatFramingAndCadence() {
    let enhanced = GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true)
    #expect(enhanced.sessionPlan.hidKeepAliveIntervalNanoseconds == 500_000_000)
    #expect(Array(enhanced.keepAliveWrites().hidOutputs[0].bytes.prefix(2)) == [0x0F, 0xF2])
    #expect(enhanced.startupWrites().isEmpty)

    let g7 = GameSirDriver(protocol: .g7ProUSB)
    #expect(g7.sessionPlan.usbKeepAliveIntervalNanoseconds == 500_000_000)
    let first = g7.keepAliveWrites().usbPackets.first
    let second = g7.keepAliveWrites().usbPackets.first
    #expect(Array(first?.bytes.prefix(6) ?? []) == [0x0F, 0x00, 0x01, 0x02, 0xF2, 0x00])
    #expect(second?.bytes[2] == 2)
  }

  @Test
  func enhancedOutputsRequireCurrentSessionAndLightingSlot() throws {
    let parser = GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true)
    #expect(parser.encoded(.setRGB(ControllerColor(red: 1, green: 2, blue: 3))) == nil)
    _ = try parser.parseReport(enhanced())
    #expect(parser.encoded(.setRGB(ControllerColor(red: 1, green: 2, blue: 3))) == nil)
    var slot = [UInt8](repeating: 0, count: 64)
    slot[0] = 0x10
    slot[1] = 0x05
    slot[2] = 0x20
    slot[5] = 1
    slot[6] = 2
    _ = try parser.parseReport(Data(slot))

    let color = try #require(parser.encoded(.setRGB(ControllerColor(red: 1, green: 2, blue: 3))))
    #expect(color.writes.hidOutputs.count == 4)
    #expect(
      Array(color.writes.hidOutputs[0].bytes.prefix(10)) == [
        0x0F, 0x03, 0x20, 0x00, 0xF9, 48, 1, 5, 20, 100,
      ]
    )
    #expect(Array(color.writes.hidOutputs[3].bytes.prefix(7)) == [0x0F, 0x03, 0x20, 0, 0, 1, 2])
    let brightness = try #require(parser.encoded(.setLightBrightness(UnipolarValue(byte: 255))))
    #expect(
      Array(brightness.writes.hidOutputs[0].bytes.prefix(7)) == [0x0F, 0x03, 0x20, 0, 0xFC, 1, 100]
    )
    #expect(
      Array(parser.rumblePlan(left: 7, right: 9, lt: 1, rt: 2).onlyReport.bytes.prefix(6)) == [
        0x0F, 0x20, 0x66, 0x55, 7, 9,
      ]
    )

    parser.resetProtocolState()
    #expect(parser.encoded(.setLightBrightness(UnipolarValue(byte: 100))) == nil)
    #expect(parser.power == nil)
  }

  /// A brightness request before the slot reply is not ready and must not change the brightness
  /// the next colour record carries.
  @Test
  func brightnessBeforeSlotReplyLeavesColourRecordUnchanged() throws {
    let parser = GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true)
    let dark = ControllerOutputCommand.setLightBrightness(.min)
    #expect(throws: ControllerOutputError.notReady) { try parser.encode(dark) }
    _ = try parser.parseReport(enhanced())
    #expect(throws: ControllerOutputError.notReady) { try parser.encode(dark) }
    #expect(throws: ControllerOutputError.notReady) {
      try parser.encode(.setRGB(ControllerColor(red: 1, green: 2, blue: 3)))
    }
    var slot = [UInt8](repeating: 0, count: 64)
    slot[0] = 0x10
    slot[1] = 0x05
    slot[2] = 0x20
    slot[5] = 1
    slot[6] = 2
    _ = try parser.parseReport(Data(slot))

    let color = try #require(parser.encoded(.setRGB(ControllerColor(red: 1, green: 2, blue: 3))))
    #expect(color.writes.hidOutputs[0].bytes[9] == 100)
    #expect(throws: ControllerOutputError.unsupportedCapability(.rgb)) {
      try GameSirDriver(protocol: .g7ProUSB).encode(
        .setRGB(ControllerColor(red: 1, green: 2, blue: 3))
      )
    }
  }

  @Test
  func eightKColorWritesAllQuadrantsAndBrightnessRegister() throws {
    let parser = GameSirDriver(protocol: .enhancedHID, hasInnerGrips: true)
    _ = try parser.parseReport(enhanced())
    let color = try #require(parser.encoded(.setRGB(ControllerColor(red: 255, green: 0, blue: 0))))
    #expect(color.writes.hidOutputs.count == 4)
    #expect(
      color.writes.hidOutputs.map { Array($0.bytes[3...4]) } == [
        [0, 12], [0, 16], [0, 20], [0, 24],
      ]
    )
    #expect(color.writes.hidOutputs.allSatisfy { Array($0.bytes[6...8]) == [0, 0, 100] })
    let brightness = try #require(parser.encoded(.setLightBrightness(UnipolarValue(byte: 128))))
    #expect(
      Array(brightness.writes.hidOutputs[0].bytes.prefix(7)) == [0x0F, 0x03, 0x20, 0, 1, 1, 50]
    )
  }

  @Test
  func g7ExposesOnlyDockBrightnessAfterGameplayStarts() throws {
    let parser = GameSirDriver(protocol: .g7ProUSB)
    #expect(parser.outputCapabilities.rumbleMotors.isEmpty)
    #expect(parser.outputCapabilities.lightingFeatures == [.programmableBrightness])
    #expect(parser.encoded(.setLightBrightness(UnipolarValue(byte: 255))) == nil)
    var report = [UInt8](repeating: 0, count: 20)
    report[1] = 0x14
    _ = try parser.parseReport(Data(report))
    let packet = try #require(
      parser.encoded(.setLightBrightness(UnipolarValue(byte: 255)))?.writes.usbPackets.first
    )
    #expect(packet.endpoint == 0x02)
    #expect(
      Array(packet.bytes.prefix(10)) == [0x0F, 0, 1, 0x3C, 0x03, 0x20, 0x01, 0xF9, 0x01, 100]
    )
  }

  @Test
  func g7BrightnessUsesBoundOutputEndpoint() throws {
    let parser = GameSirDriver(protocol: .g7ProUSB, outEndpoint: 0x05)
    var report = [UInt8](repeating: 0, count: 20)
    report[1] = 0x14
    _ = try parser.parseReport(Data(report))
    #expect(
      parser.encoded(.setLightBrightness(UnipolarValue(byte: 255)))?.writes.usbPackets.map(
        \.endpoint
      ) == [0x05]
    )
  }

  private func enhanced(
    leftX: UInt8 = 128,
    leftY: UInt8 = 128,
    rightX: UInt8 = 128,
    rightY: UInt8 = 128,
    face: UInt8 = 0,
    meta: UInt8 = 0,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    counter: UInt8 = 0,
    extras: UInt8 = 0,
    battery: UInt8 = 50,
    charging: Bool = false
  ) -> Data {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 0x12
    report[1] = leftX
    report[2] = leftY
    report[3] = rightX
    report[4] = rightY
    report[5] = face
    report[6] = meta
    report[7] = counter
    report[8] = leftTrigger
    report[9] = rightTrigger
    report[35] = charging ? 1 : 0
    report[36] = battery
    report[60] = extras
    return Data(report)
  }
}

struct GameSirCatalogTests {
  private func protocolID(
    _ registry: ProtocolDriverRegistry,
    _ vendorID: UInt16,
    _ productID: UInt16
  ) -> PhysicalProtocolID? {
    registry.record(for: ControllerModelID(vendorID: vendorID, productID: productID))?
      .physicalProtocolID
  }

  @Test
  func routesSourceBackedIdentitiesWithoutChangingExistingLinuxPaths() throws {
    let registry = ProtocolDriverRegistry()
    let g7: [UInt16] = [0x1003, 0x105D, 0x105E, 0x109B, 0x109C, 0x10BA]
    let enhanced: [UInt16] = [0x0575, 0x100B, 0x1053, 0x10C5, 0x10C6, 0x10C7, 0x10C8]
    for productID in g7 + enhanced {
      let model = ControllerModelID(vendorID: 0x3537, productID: productID)
      #expect(registry.record(for: model)?.physicalProtocolID == .vendorGameSir)
      #expect(try catalogParser(model, registry: registry) is GameSirDriver)
    }
    #expect(protocolID(registry, 0x3537, 0x1004) == .xboxXUSB)
    #expect(protocolID(registry, 0x3537, 0x100F) == .xboxXUSB)
    #expect(protocolID(registry, 0x3537, 0x1010) == .xboxGIP)
    for productID: UInt16 in [0x02FD, 0x02FF] {
      #expect(protocolID(registry, 0x045E, productID) != .vendorGameSir)
    }
  }

  @Test
  func inputOnlyIdentitiesDoNotExposeConfigurationOutputs() throws {
    let registry = ProtocolDriverRegistry()
    let transition = ControllerModelID(vendorID: 0x3537, productID: 0x100A)
    let native = ControllerModelID(vendorID: 0x3537, productID: 0x1022)
    #expect(try catalogParser(transition, registry: registry) is HIDDescriptorDriver)
    #expect(
      (try catalogParser(native, registry: registry) as? GIPDriver)?.outputCapabilities.rumbleMotors
        .isEmpty == true
    )
    #expect(registry.record(for: native)?.capabilityDelta.rumbleAbsent == true)
  }
}
