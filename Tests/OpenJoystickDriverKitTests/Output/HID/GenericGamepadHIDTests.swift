import Testing

@testable import OpenJoystickDriverKit

struct GenericGamepadHIDTests {
  @Test
  func identityAndDescriptorBytesRemainStable() {
    // Arrange
    let profile = VirtualDeviceProfile.openJoystickDriverGenericHID

    // Act
    let descriptorHash = GamepadHIDDescriptor.descriptor.reduce(UInt64(0xCBF2_9CE4_8422_2325)) {
      ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3
    }

    // Assert
    #expect(profile.vendorID == 0x1209)
    #expect(profile.productID == 0x4A4F)
    #expect(profile.versionNumber == 0x0408)
    #expect(profile.productName == "OpenJoystickDriver Generic HID Gamepad")
    #expect(profile.manufacturer == "OpenJoystickDriver")
    #expect(profile.transport == "USB")
    #expect(GamepadHIDDescriptor.descriptor.count == 60)
    #expect(descriptorHash == 0x1ECB_8E98_9A22_47A8)
  }

  @Test
  func descriptorPublishesBlinkButtonsAndSixAxes() throws {
    // Arrange
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: GamepadHIDDescriptor.descriptor)
    )

    // Act
    let buttons = parsed.fields.filter { $0.usagePage == 0x09 }
    let axes = parsed.fields.filter { $0.usagePage == 0x01 }

    // Assert
    #expect(parsed.payloadSizeBytesByReportID[0] == 14)
    #expect(buttons.map(\.usage) == Array(1...6) + Array(9...18))
    #expect(buttons.map(\.bitOffset) == Array(0...15))
    #expect(axes.map(\.usage) == [0x30, 0x31, 0x32, 0x33, 0x34, 0x35])
    #expect(axes.map(\.bitOffset) == [16, 32, 48, 64, 80, 96])
    #expect(!axes.contains { $0.usage == 0x39 })
    #expect(axes.allSatisfy { $0.logicalMin == -32_767 && $0.logicalMax == 32_767 })
  }

  @Test
  func normalizedButtonsSerializeToTheirPublishedUsages() {
    // Arrange
    let mappings: [(GamepadHIDDescriptor.ButtonBit, usage: Int)] = [
      (.a, 1), (.b, 2), (.x, 3), (.y, 4), (.leftBumper, 5), (.rightBumper, 6), (.back, 9),
      (.start, 10), (.leftStick, 11), (.rightStick, 12), (.dpadUp, 13), (.dpadDown, 14),
      (.dpadLeft, 15), (.dpadRight, 16), (.guide, 17), (.share, 18),
    ]
    let format = OJDGenericGamepadFormat()
    let fields = HIDReportDescriptorParser.parse(descriptor: format.descriptor)?.fields.filter {
      $0.usagePage == 0x09
    }

    // Act and assert
    for (destination, mapping) in mappings.enumerated() {
      let report = format.buildInputReport(
        from: VirtualGamepadState(buttons: 1 << UInt32(mapping.0.rawValue))
      )
      let packed = UInt32(report[0]) | (UInt32(report[1]) << 8)
      #expect(packed == 1 << UInt32(destination))
      #expect(fields?[destination].usage == mapping.usage)
      #expect(fields?[destination].bitOffset == destination)
    }
  }

  @Test
  func reportContainsSixAxesInBlinkOrder() {
    // Arrange
    let format = OJDGenericGamepadFormat()
    let state = VirtualGamepadState(
      leftStickX: 0x0102,
      leftStickY: 0x0304,
      rightStickX: 0x0506,
      rightStickY: 0x0708,
      leftTrigger: 0x090A,
      rightTrigger: 0x0B0C
    )

    // Act
    let report = format.buildInputReport(from: state)

    // Assert
    #expect(report.count == 14)
    #expect(
      Array(report[2...13]) == [
        0x02, 0x01, 0x04, 0x03, 0x06, 0x05, 0x08, 0x07, 0x0A, 0x09, 0x0C, 0x0B,
      ]
    )
  }

  @Test
  func analogTriggersPreserveNeutralPartialFullAndReleaseValues() {
    // Arrange
    let format = OJDGenericGamepadFormat()
    let values: [(Int16, [UInt8])] = [
      (0, [0x00, 0x00]), (16_384, [0x00, 0x40]), (32_767, [0xFF, 0x7F]), (0, [0x00, 0x00]),
    ]

    // Act and assert
    for (value, expectedBytes) in values {
      let report = format.buildInputReport(
        from: VirtualGamepadState(leftTrigger: value, rightTrigger: value)
      )
      #expect(Array(report[10...11]) == expectedBytes)
      #expect(Array(report[12...13]) == expectedBytes)
    }
  }

  @Test
  func digitalTriggersUseFullScaleAxesWithoutButtonDuplicates() {
    // Arrange
    let format = OJDGenericGamepadFormat()

    // Act
    let report = format.buildInputReport(
      from: VirtualGamepadState(leftTriggerPressed: true, rightTriggerPressed: true)
    )

    // Assert
    #expect(Array(report[0...1]) == [0, 0])
    #expect(Array(report[10...13]) == [0xFF, 0x7F, 0xFF, 0x7F])
  }

  @Test
  func descriptorAndFormatAreInputOnly() throws {
    // Arrange
    let format = OJDGenericGamepadFormat()
    let parsed = try #require(HIDReportDescriptorParser.parse(descriptor: format.descriptor))

    // Act
    let outputItems = Self.mainItemCount(tag: 0x9, in: format.descriptor)

    // Assert
    #expect(outputItems == 0)
    #expect(!parsed.containsFeatureItem)
    #expect(format.outputReportPayloadSize == nil)
    #expect(format.outputReportID == nil)
  }

  /// Counts short main items with `tag` (0x9 is Output) by walking the descriptor's items.
  private static func mainItemCount(tag: UInt8, in descriptor: [UInt8]) -> Int {
    var count = 0
    var index = 0
    while index < descriptor.count {
      let prefix = descriptor[index]
      let size = prefix & 0x03 == 0x03 ? 4 : Int(prefix & 0x03)
      if (prefix >> 2) & 0x03 == 0, prefix >> 4 == tag { count += 1 }
      index += 1 + size
    }
    return count
  }
}
