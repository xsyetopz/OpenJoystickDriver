import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileTests {
  @Test
  func exactlyThreeApprovedProfileIDsExist() {
    #expect(
      VirtualHIDProfileID.allCases.map(\.rawValue) == [
        "SDLCompatible", "Generic", "GameControllerCompatible",
      ]
    )
  }

  @Test(arguments: [
    "generic-hid", "automatic", "sdl2-3", "apple-gamecontroller", "SDLCompatible-v2",
    "SdlCompatible",
    "NotAPersona", "",
  ])
  func anyOtherProfileIDIsRejected(rawValue: String) throws {
    #expect(VirtualHIDProfileID(rawValue: rawValue) == nil)
    let json = try JSONEncoder().encode(rawValue)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(VirtualHIDProfileID.self, from: json)
    }
  }

  @Test
  func approvedProfileIDsRoundTripThroughCodable() throws {
    for id in VirtualHIDProfileID.allCases {
      let json = try JSONEncoder().encode(id)
      #expect(String(bytes: json, encoding: .utf8) == "\"\(id.rawValue)\"")
      #expect(try JSONDecoder().decode(VirtualHIDProfileID.self, from: json) == id)
    }
  }

  @Test
  func everyIDResolvesToItsProfile() {
    for id in VirtualHIDProfileID.allCases { #expect(id.makeProfile().id == id) }
  }

  @Test
  func sdlCompatibleProfileAdaptsXboxOneGIPLayout() {
    let profile = VirtualHIDProfileID.sdlCompatible.makeProfile()
    #expect(profile.identity == .sdlCompatible)
    #expect(profile.identity.vendorID == 0x045E && profile.identity.productID == 0x0B0C)
    #expect(profile.descriptor == XboxOneGIPHIDDescriptor.descriptor)
    let neutral = profile.inputReport(for: .neutral)
    #expect(neutral == ProtocolPacketFixtures.XboxOneGIP.neutralInputReport)
    #expect(neutral == XboxOneGIPHIDReportFormat().buildInputReport(from: VirtualGamepadState()))
  }

  @Test
  func genericProfileAdaptsCurrentOJDGenericGamepad() {
    let profile = VirtualHIDProfileID.generic.makeProfile()
    #expect(profile.identity == .generic)
    #expect(profile.descriptor == GamepadHIDDescriptor.descriptor)
    let neutral = profile.inputReport(for: .neutral)
    #expect(neutral == [UInt8](repeating: 0, count: 14))
    #expect(neutral == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState()))

    // South, stick at full up: negative Y in the state, and the Y-down report carries it as is.
    let pressed = ControllerState(
      pressed: [.south],
      leftStick: StickPosition(x: .center, y: BipolarValue(-Int16.max))
    )
    #expect(
      profile.inputReport(for: pressed) == [
        0x01, 0x00, 0x00, 0x00, 0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]
    )
  }

  @Test
  func xboxProfileDecodesOnlyItsOwnRumbleReport() throws {
    let profile = VirtualHIDProfileID.sdlCompatible.makeProfile()
    let report = gipRumbleReport(
      activation: 0x0F,
      leftTrigger: 10,
      rightTrigger: 20,
      left: 30,
      right: 40,
      duration: 50
    )
    let expected = ControllerOutputCommand.consumerRumble(
      left: 30,
      right: 40,
      leftTrigger: 10,
      rightTrigger: 20,
      durationMs: 500
    )
    #expect(
      profile.consumerOutput(type: .output, reportID: 9, bytes: report) == expected
    )
    #expect(try consumerOutput(9, report, in: XboxOneGIPHIDReportFormat()) == expected)
    #expect(
      profile.consumerOutput(
        type: .output,
        reportID: 0,
        bytes: Self.unnumberedVendorReport
      ) == nil
    )
    #expect(profile.consumerOutput(type: .input, reportID: 9, bytes: report) == nil)
    #expect(
      profile.consumerOutput(type: .feature, reportID: 9, bytes: report) == nil
    )
    #expect(
      profile.consumerOutput(
        type: .output,
        reportID: 9,
        bytes: gipRumbleReport(activation: 0x0F, duration: 50)
      ) == .stopRumble
    )
    // The short report the set-report callback rejects is rejected by the profile's codec too.
    #expect(
      profile.consumerOutput(
        type: .output,
        reportID: 9,
        bytes: [0x09, 0x00, 0x00, 0x09, 0x00, 0x0F, 10, 20, 30, 40]
      ) == nil
    )
  }

  @Test
  func genericProfileInputOnlyAndDecodesNoOutputReport() {
    let profile = VirtualHIDProfileID.generic.makeProfile()
    #expect(profile.identity.vendorID == 0x1209)
    #expect(profile.identity.productID == 0x4A4F)
    #expect(profile.reportFormat.outputReportPayloadSize == nil)
    let reports: [(UInt32, [UInt8])] = [
      (0, Self.unnumberedVendorReport), (0, [0x08, 0x00, 10, 20]),
      (3, [0x03, 0x0F, 10, 20, 30, 40, 50, 0, 0]),
    ]
    for (reportID, bytes) in reports {
      #expect(
        profile.consumerOutput(type: .output, reportID: reportID, bytes: bytes)
          == nil
      )
    }
  }

  @Test
  func xboxProfileRepresentsSpecXboxLayout() {
    let profile = VirtualHIDProfileID.sdlCompatible
    let layout: Set<Control> = Control.dpad.union([
      .south, .east, .west, .north, .leftShoulder, .rightShoulder,
      .leftTrigger, .rightTrigger, .leftStickX, .leftStickY, .rightStickX, .rightStickY,
      .leftStickClick, .rightStickClick, .back, .start,
    ])
    #expect(profile.representableControls == layout)
  }

  @Test
  func genericProfileRepresentsSpecGenericLayout() {
    let profile = VirtualHIDProfileID.generic
    let buttons: [Control] = [
      .south, .east, .west, .north, .leftShoulder, .rightShoulder,
      .leftTrigger, .rightTrigger, .back, .start, .leftStickClick, .rightStickClick,
      .guide, .capture, .touchpadClick, .leftPaddle1, .leftPaddle2, .rightPaddle1,
      .rightPaddle2, .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6,
      .auxiliary7, .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick,
      .rightTrackpadClick,
    ]
    let hatAndAxes = Control.dpad.union([
      .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftTrigger, .rightTrigger,
    ])
    // The frozen 32 button slots held Share and Capture apart; one id, Capture, fills both.
    #expect(buttons.count == 31)
    #expect(profile.representableControls == Set(buttons).union(hatAndAxes))
    #expect(
      Set(Control.allCases).subtracting(profile.representableControls) == [
        .microphone, .leftTrackpadTouch, .rightTrackpadTouch, .pointerX, .pointerY,
        .pointerTracking, .leftGripTouch, .rightGripTouch,
      ]
    )
  }

  /// An unnumbered vendor report: marker `0x4F`, four motor bytes, and a little-endian 500.
  ///
  /// No virtual HID profile reads it.
  private static let unnumberedVendorReport: [UInt8] = [0x4F, 1, 2, 3, 4, 0xF4, 0x01]
}
