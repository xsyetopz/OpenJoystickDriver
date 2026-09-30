import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Advertised output capabilities agree with the driver's encoders for every catalog row.
extension DriverLifecycleCharacterizationTests {
  /// Every registry-built driver, readied with its family and variant subject's input, has a
  /// plan with writes for each capability it advertises; an encoder returns nil only where the
  /// capability is absent. A row whose family and variant has no subject fails.
  @Test
  func advertisedOutputCapabilitiesHaveEncoders() throws {
    let identifiers = Self.registry.rawUSBIdentifiers + Self.registry.hidIdentifiers
    var checked = 0
    for identifier in identifiers {
      let record = try #require(Self.registry.record(for: identifier))
      let hosts: [PhysicalTransport] =
        record.usesRawUSB
        ? [.usb]
        : record.quirks.contains(.switch2) ? [.usb, .bluetoothLE] : [.usb, .bluetoothClassic]
      for host in hosts {
        let device = PhysicalDevice(
          vendorID: identifier.controllerIdentity.vendorID,
          productID: identifier.controllerIdentity.productID,
          interfaces: record.usesRawUSB ? nil : [gamepadHIDInterface(host: host)]
        )
        let backend: DeviceAccessBackend = record.usesRawUSB ? .ioUSBHost : .ioHID
        guard case .bound(let binding) = Self.registry.classify(device, backend: backend) else {
          continue
        }
        let candidates =
          [Self.tritonDongle, Self.steamBluetoothLE, Self.switch2BluetoothLE] + Self.subjects
        let family = candidates.filter {
          $0.protocolID == binding.protocolID && $0.variant == binding.variant
        }
        // A quirk can select another driver in the same family and variant, with other input.
        guard
          let subject = family.first(where: { Set($0.quirks) == Set(record.quirks) })
            ?? family.first
        else {
          Issue.record("\(identifier) binds \(binding.protocolID) with no subject")
          continue
        }
        let driver = try Self.registry.makeDriver(
          for: binding,
          identifier: identifier,
          claimed: record.usesRawUSB
            ? USBTransportResolution(profile: record.transportProfile) : nil
        ).get()
        feed(driver, subject.readyingInput)
        expectEncoders(driver, match: driver.outputCapabilities, "\(identifier) \(host)")
        checked += 1
      }
    }
    #expect(checked > Self.subjects.count)
  }

  func expectEncoders(
    _ driver: any PhysicalProtocolDriver,
    match caps: PhysicalControllerOutputCapabilities,
    _ row: String
  ) {
    // Advertised implies writes, so a nil encoder implies an absent capability. The converse
    // does not hold: GameSir USB encodes a HID rumble report and has a default colour without
    // advertising either (pinned in its transcript).
    func expect(_ plan: PhysicalOutputPlan?, advertised: Bool, _ output: String) {
      guard advertised else { return }
      #expect(plan?.writes.isEmpty == false, "\(row): \(output) advertised without writes")
    }
    expect(
      driver.encoded(
        .setRumble(RumbleIntensities(bytes: Self.rumbleIntensities), duration: .milliseconds(100))
      ),
      advertised: caps.supportsRumble,
      "rumble"
    )
    for indicator in PhysicalPlayerIndicator.allCases {
      expect(
        driver.encoded(.setPlayerIndicator(indicator)),
        advertised: caps.supportsPlayerIndicator,
        "player indicator \(indicator)"
      )
    }
    let color = caps.lightingFeatures.contains(.programmableColor)
    expect(
      driver.encoded(.setRGB(ControllerColor(red: 1, green: 2, blue: 3))),
      advertised: color,
      "colour"
    )
    #expect(!color || driver.defaultColor != nil, "\(row): colour without a default colour")
    expect(
      driver.encoded(.setLightBrightness(UnipolarValue(byte: 0x80))),
      advertised: caps.supportsProgrammableBrightness,
      "brightness"
    )
    for trigger in PhysicalAdaptiveTrigger.allCases {
      expect(
        driver.encoded(.setAdaptiveTrigger(trigger, Self.triggerResistance)),
        advertised: caps.adaptiveTriggers.contains(trigger),
        "adaptive trigger \(trigger)"
      )
    }
  }
}
