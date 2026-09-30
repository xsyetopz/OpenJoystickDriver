import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileTests {
  @Test
  func exactlyTheTwoApprovedProfileIDsExist() {
    #expect(VirtualHIDProfileID.allCases.map(\.rawValue) == ["hid-xbox-one-s-bt", "hid-generic"])
  }

  @Test(arguments: [
    "generic-hid", "automatic", "sdl2-3", "apple-gamecontroller", "hid-xbox-one-s-bt-v2",
    "HID-GENERIC", "",
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
  func everyIDResolvesToItsProfile() throws {
    for id in VirtualHIDProfileID.allCases { #expect(try id.makeProfile().id == id) }
  }

  @Test
  func xboxProfileAdaptsTheCurrentXboxOneSApproximation() throws {
    let profile = try VirtualHIDProfileID.xboxOneSBluetooth.makeProfile()
    #expect(profile.identity == .xboxOneS)
    #expect(profile.identity.vendorID == 0x045E && profile.identity.productID == 0x02FD)
    #expect(profile.descriptor == XboxOneBluetoothHIDDescriptor.oneSDescriptor)
    let neutral = profile.inputReport(for: .neutral)
    #expect(
      neutral == [
        0x01, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
      ]
    )
    #expect(
      neutral == (try XboxGeckoHIDReportFormat()).buildInputReport(from: VirtualGamepadState())
    )
  }

  @Test
  func genericProfileAdaptsTheCurrentOJDGenericGamepad() throws {
    let profile = try VirtualHIDProfileID.generic.makeProfile()
    #expect(profile.identity == .openJoystickDriverGenericHID)
    #expect(profile.descriptor == GamepadHIDDescriptor.descriptor)
    let neutral = profile.inputReport(for: .neutral)
    #expect(neutral == [UInt8](repeating: 0, count: 14))
    #expect(neutral == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState()))

    // South, Y-up canonical stick at full up, which the report carries Y-down.
    let pressed = ControllerState(
      pressed: [.faceSouth],
      leftStick: StickPosition(x: .center, y: BipolarValue(Int16.max))
    )
    #expect(
      profile.inputReport(for: pressed) == [
        0x01, 0x00, 0x00, 0x00, 0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]
    )
  }

  @Test
  func xboxProfileDecodesOnlyItsOwnRumbleReport() throws {
    let profile = try VirtualHIDProfileID.xboxOneSBluetooth.makeProfile()
    let report: [UInt8] = [0x03, 0x0F, 10, 20, 30, 40, 50, 0, 0]
    let expected = ControllerOutputCommand.consumerRumble(
      left: 30,
      right: 40,
      leftTrigger: 10,
      rightTrigger: 20,
      durationMs: 500
    )
    #expect(
      profile.consumerOutput(type: kIOHIDReportTypeOutput, reportID: 3, bytes: report) == expected
    )
    #expect(try consumerOutput(3, report, in: XboxGeckoHIDReportFormat()) == expected)
    #expect(
      profile.consumerOutput(type: kIOHIDReportTypeOutput, reportID: 0, bytes: Self.ojdRumble)
        == nil
    )
    #expect(profile.consumerOutput(type: kIOHIDReportTypeInput, reportID: 3, bytes: report) == nil)
    #expect(
      profile.consumerOutput(type: kIOHIDReportTypeFeature, reportID: 3, bytes: report) == nil
    )
    #expect(
      profile.consumerOutput(
        type: kIOHIDReportTypeOutput,
        reportID: 3,
        bytes: [0x03, 0x0F, 0, 0, 0, 0, 50, 0, 0]
      ) == .stopRumble
    )
    // The short report the set-report callback rejects is rejected by the profile's codec too.
    #expect(
      profile.consumerOutput(
        type: kIOHIDReportTypeOutput,
        reportID: 3,
        bytes: [0x03, 0x0F, 10, 20, 30, 40]
      ) == nil
    )
  }

  @Test
  func genericProfileIsInputOnlyAndDecodesNoOutputReport() throws {
    let profile = try VirtualHIDProfileID.generic.makeProfile()
    #expect(profile.identity.vendorID == 0x1209)
    #expect(profile.identity.productID == 0x4A4F)
    #expect(profile.reportFormat.outputReportPayloadSize == nil)
    let reports: [(UInt32, [UInt8])] = [
      (0, Self.ojdRumble), (0, [0x08, 0x00, 10, 20]), (3, [0x03, 0x0F, 10, 20, 30, 40, 50, 0, 0]),
    ]
    for (reportID, bytes) in reports {
      #expect(
        profile.consumerOutput(type: kIOHIDReportTypeOutput, reportID: reportID, bytes: bytes)
          == nil
      )
    }
  }

  @Test
  func xboxProfileRepresentsTheSpecXboxLayout() {
    let profile = VirtualHIDProfileID.xboxOneSBluetooth
    let layout: Set<ControlID> = [
      .dpad, .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder,
      .leftTrigger, .rightTrigger, .leftStickX, .leftStickY, .rightStickX, .rightStickY,
      .leftStickClick, .rightStickClick, .view, .menu,
    ]
    #expect(profile.representableControls == layout)
  }

  @Test
  func genericProfileRepresentsTheSpecGenericLayout() {
    let profile = VirtualHIDProfileID.generic
    let buttons: [ControlID] = [
      .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder,
      .leftTriggerButton, .rightTriggerButton, .view, .menu, .leftStickClick, .rightStickClick,
      .guide, .share, .capture, .touchpadClick, .paddleLeft1, .paddleLeft2, .paddleRight1,
      .paddleRight2, .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6,
      .auxiliary7, .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick,
      .rightTrackpadClick,
    ]
    let hatAndAxes: Set<ControlID> = [
      .dpad, .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftTrigger, .rightTrigger,
    ]
    #expect(buttons.count == 32)
    #expect(profile.representableControls == Set(buttons).union(hatAndAxes))
    #expect(
      Set(ControlID.allCases).subtracting(profile.representableControls) == [
        .microphone, .leftTrackpadTouch, .rightTrackpadTouch,
      ]
    )
  }

  /// The former OJD vendor rumble report: marker, left, right, left trigger, right trigger,
  /// duration 500 ms LE.
  private static let ojdRumble: [UInt8] = [0x4F, 1, 2, 3, 4, 0xF4, 0x01]
}
