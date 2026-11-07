import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerCapabilitiesTests {
  private static let triggerButtons: Set<Control> = [.leftTrigger, .rightTrigger]
  private static let xbox = Control.xboxLayout
  private static let xboxGuide = xbox.union([.guide])
  /// Analog triggers without a digital signal get normalization-derived trigger buttons.
  private static let normalizedXbox = xbox.union(triggerButtons)
  private static let normalizedXboxGuide = xboxGuide.union(triggerButtons)
  private static let dualSense = xboxGuide.union(triggerButtons).union([
    .touchpadClick, .microphone,
  ])
  private static let switchPro = xbox.subtracting([.leftTrigger, .rightTrigger]).union(
    triggerButtons
  ).union([.guide, .capture])
  private static let gameSirG7Pro = normalizedXboxGuide.union([
    .leftPaddle1, .rightPaddle1, .leftPaddle2, .rightPaddle2, .auxiliary1,
  ])

  static let golden: [(String, UInt16, UInt16, ControllerCapabilities)] = [
    ("XID", 0x045E, 0x0202, ControllerCapabilities(controls: normalizedXbox)),
    ("XUSB wired", 0x045E, 0x028E, ControllerCapabilities(controls: normalizedXboxGuide)),
    ("XUSB receiver", 0x045E, 0x0719, ControllerCapabilities(controls: normalizedXboxGuide)),
    ("GIP", 0x045E, 0x02EA, ControllerCapabilities(controls: normalizedXboxGuide)),
    (
      "GIP share offset", 0x045E, 0x0B12,
      ControllerCapabilities(controls: normalizedXboxGuide.union([.capture]))
    ), ("DS3", 0x054C, 0x0268, ControllerCapabilities(controls: xboxGuide.union(triggerButtons))),
    (
      "DS4", 0x054C, 0x05C4,
      ControllerCapabilities(
        controls: xboxGuide.union(triggerButtons).union([.touchpadClick]),
        touchContactCount: 2,
        motion: true
      )
    ),
    (
      "DualSense", 0x054C, 0x0CE6,
      ControllerCapabilities(controls: dualSense, touchContactCount: 2, motion: true)
    ),
    (
      "DualSense Edge", 0x054C, 0x0DF2,
      ControllerCapabilities(
        controls: dualSense.union([.leftPaddle1, .rightPaddle1, .auxiliary1, .auxiliary2]),
        touchContactCount: 2,
        motion: true
      )
    ), ("Switch Pro", 0x057E, 0x2009, ControllerCapabilities(controls: switchPro, motion: true)),
    (
      "Joy-Con L", 0x057E, 0x2006,
      ControllerCapabilities(
        controls: [
          .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .leftStickClick,
          .leftShoulder, .leftTrigger,
          .back, .capture, .auxiliary3, .auxiliary4,
        ],
        motion: true
      )
    ),
    (
      "Joy-Con R", 0x057E, 0x2007,
      ControllerCapabilities(
        controls: [
          .south, .east, .west, .north, .rightStickX, .rightStickY,
          .rightStickClick, .rightShoulder, .rightTrigger, .start, .guide, .auxiliary5,
          .auxiliary6,
        ],
        motion: true
      )
    ),
    (
      "Steam Controller", 0x28DE, 0x1102,
      ControllerCapabilities(
        controls: xbox.subtracting([.rightStickClick]).union(triggerButtons).union([
          .guide, .leftPaddle2, .rightPaddle2, .leftTrackpadClick, .rightTrackpadClick,
          .leftTrackpadTouch, .rightTrackpadTouch,
        ]),
        touchContactCount: 1,
        motion: true
      )
    ),
    (
      "Flydigi", 0xD7D7, 0x0041,
      ControllerCapabilities(
        controls: xboxGuide.union(triggerButtons).union([
          .auxiliary1, .auxiliary2, .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2,
        ])
      )
    ),
    ("GameSir G7 Pro", 0x3537, 0x1003, ControllerCapabilities(controls: gameSirG7Pro)),
    // GameSir motion has no verified scale or frame, so no GameSir row declares motion.
    ("GameSir G7 Pro 8K", 0x3537, 0x10C5, ControllerCapabilities(controls: gameSirG7Pro)),
    (
      "GameSir Cyclone 2", 0x3537, 0x100B,
      ControllerCapabilities(
        controls: normalizedXboxGuide.union([.leftPaddle1, .rightPaddle1, .auxiliary1])
      )
    ), (
      "Generic HID", 0x2E95, 0x434D,
      ControllerCapabilities(controls: normalizedXboxGuide.union([.capture]))
    ),
    (
      "GIP analog triggers absent", 0x0738, 0x4A01,
      ControllerCapabilities(
        controls: normalizedXboxGuide.subtracting([.leftTrigger, .rightTrigger])
      )
    ),
    (
      "XID sticks and analog triggers absent", 0x0C12, 0x8809,
      ControllerCapabilities(
        controls: normalizedXbox.subtracting([
          .leftTrigger, .rightTrigger, .leftStickX, .leftStickY, .rightStickX, .rightStickY,
        ])
      )
    ),
  ]

  @Test(arguments: golden)
  func catalogProfilesDeclareTheParserControlSet(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    expected: ControllerCapabilities
  ) throws {
    let model = ControllerModelID(vendorID: vendorID, productID: productID)
    let capabilities = try #require(ProtocolDriverRegistry().profileCapabilities(for: model))
    #expect(capabilities.physicalInput == expected, "\(name)")
    let data = try JSONEncoder().encode(capabilities.physicalInput)
    #expect(try JSONDecoder().decode(ControllerCapabilities.self, from: data) == expected)
  }

  @Test
  func encodingListsControlsInCanonicalOrder() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(
      ControllerCapabilities(
        controls: [.guide, .start, .dpadUp, .dpadDown, .dpadLeft, .dpadRight],
        touchContactCount: 1,
        motion: true
      )
    )
    #expect(
      String(bytes: data, encoding: .utf8)
        == #"{"controls":["Start","DpadUp","DpadDown","DpadLeft","DpadRight","Guide"],"#
        + #""motion":true,"touchContactCount":1}"#
    )
  }

  @Test(arguments: [
    #"{"controls":["dpad","turbo"],"touchContactCount":0,"motion":false}"#,
    #"{"controls":["dpad"],"touchContactCount":0}"#, #"{"controls":["dpad"],"motion":false}"#,
    #"{"touchContactCount":0,"motion":false}"#,
  ])
  func decodingRejectsUnknownControlsAndMissingKeys(_ json: String) {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ControllerCapabilities.self, from: Data(json.utf8))
    }
  }

  @Test
  func touchSurfacesFollowTrackpadControls() {
    #expect(ControllerCapabilities(controls: [.touchpadClick]).touchSurfaces.isEmpty)
    #expect(
      ControllerCapabilities(controls: [.touchpadClick], touchContactCount: 2).touchSurfaces == [
        .primary
      ]
    )
    #expect(
      ControllerCapabilities(
        controls: [.rightTrackpadTouch, .leftTrackpadTouch],
        touchContactCount: 1
      ).touchSurfaces == [.left, .right]
    )
    #expect(
      ControllerCapabilities(controls: [.rightTrackpadTouch], touchContactCount: 1).touchSurfaces
        == [.right]
    )
  }

  @Test
  func intersectionKeepsSharedControlsAndTheWeakerSampleFormats() {
    let first = ControllerCapabilities(
      controls: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight, .guide, .touchpadClick],
      touchContactCount: 2,
      motion: true
    )
    let second = ControllerCapabilities(
      controls: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight, .touchpadClick, .capture],
      touchContactCount: 1
    )
    #expect(
      first.intersecting(second)
        == ControllerCapabilities(
          controls: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight, .touchpadClick],
          touchContactCount: 1
        )
    )
  }
}
