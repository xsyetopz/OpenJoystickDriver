import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Report 1 of the NITHO MLT-KRMA-K in V3 mode ("BSP-G6S"), as hex bytes from the maintainer's
/// capture in `docs/testing/nitho-mlt-krma-k.md`.
private func v3Report(_ hex: String) -> Data {
  Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
}

private let v3Model = ControllerModelID(vendorID: 0x1949, productID: 0x0402)

/// A report whose first slot holds `contact` and whose other three slots are zero.
private func oneContact(_ contact: String) -> Data {
  v3Report("01 " + contact + String(repeating: " 00", count: 12) + " 01")
}

@Suite
struct NithoV3TouchLayoutTests {
  private func driver() throws -> ReportLayoutDriver {
    try #require(
      try catalogParser(v3Model, host: .bluetoothLE, modeID: "v3") as? ReportLayoutDriver
    )
  }

  /// The Manba One gamepad shares the model ID over USB, so only the Bluetooth LE link runs V3, and
  /// USB runs the HID descriptor family with no touch layout.
  @Test
  func touchIdentitySelectsV3AndOtherIdentitiesRunDefault() async throws {
    let profile = try #require(ProtocolDriverRegistry().record(for: v3Model))
    func select(
      _ link: PhysicalTransport,
      named productName: String = "BSP-G6S"
    ) async -> ControllerModeSelection {
      let device = PhysicalDevice(
        vendorID: v3Model.vendorID,
        productID: v3Model.productID,
        productName: productName,
        interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: link)]
      )
      return await ControllerModeSelector.select(
        from: profile,
        model: v3Model,
        backend: .hid,
        reader: UnreadableModeProbeReader(),
        device: device
      ) { _ in }
    }
    #expect(await select(.bluetoothLE) == .matched("v3"))
    #expect(await select(.bluetoothLE, named: "BSP-G6S-HID") == .noModeMatched)
    #expect(await select(.usb) == .noModeMatched)
    #expect(try catalogParser(v3Model, host: .usb) is HIDDescriptorDriver)
  }

  @Test
  func tapOnSpotHoldsItsButtonUntilLift() throws {
    let driver = try driver()
    #expect(try driver.parseReport(oneContact("03 2d a4 ef"))?.state.pressed == [.south])
    #expect(try driver.parseReport(oneContact("02 2d a4 ef"))?.state.pressed.isEmpty == true)
  }

  @Test
  func triggerSpotPullsTriggerFully() throws {
    let driver = try driver()
    #expect(try driver.parseReport(oneContact("03 a2 96 f0"))?.state.leftTrigger.normalized == 1)
  }

  @Test
  func twoContactsOfDpadDownReadSouth() throws {
    let driver = try driver()
    let down = v3Report("01 03 40 64 ad 13 47 c5 80 00 00 00 00 00 00 00 00 02")
    #expect(try driver.parseReport(down)?.state.hat == .south)
    let lift = v3Report("01 02 40 64 ad 12 47 c5 80 00 00 00 00 00 00 00 00 02")
    #expect(try driver.parseReport(lift)?.state.hat == .neutral)
  }

  @Test
  func dragFromLeftStickCenterPushesStickUp() throws {
    let driver = try driver()
    #expect(try driver.parseReport(oneContact("03 6b 93 29"))?.state.leftStick == .center)
    let held = try #require(try driver.parseReport(oneContact("03 f6 96 29"))?.state)
    #expect(held.leftStick.y.normalized == -1)
    #expect(held.pressed.isEmpty)
    #expect(try driver.parseReport(oneContact("02 f6 96 29"))?.state.leftStick == .center)
  }

  @Test
  func dragFromRightStickCenterPushesStickRight() throws {
    let driver = try driver()
    _ = try driver.parseReport(oneContact("03 f6 66 c9"))
    let held = try #require(try driver.parseReport(oneContact("03 f6 b6 f4"))?.state)
    #expect(abs(held.rightStick.x.normalized - 693.0 / 800) < 0.001)
    #expect(held.rightStick.y.normalized == 0)
  }

  /// LB's spot (2401, 3184) lies in the right stick's travel; a drag that reaches it stays a drag.
  @Test
  func dragOntoSpotPressesNothing() throws {
    let driver = try driver()
    _ = try driver.parseReport(oneContact("03 f6 66 c9"))
    let held = try #require(try driver.parseReport(oneContact("03 61 09 c7"))?.state)
    #expect(held.pressed.isEmpty)
    #expect(held.rightStick.y.normalized < -0.7)
  }

  @Test
  func contactAwayFromEverySpotPressesNothing() throws {
    let driver = try driver()
    let state = try #require(try driver.parseReport(oneContact("03 00 08 80"))?.state)
    #expect(state == .neutral)
  }

  @Test
  func capabilitiesListTouchControls() throws {
    let controls = try driver().capabilities.controls
    #expect(controls.isSuperset(of: [.south, .dpadDown, .leftTrigger, .rightStickX, .leftStickY]))
    #expect(!controls.contains(.rightShoulder))
  }
}
