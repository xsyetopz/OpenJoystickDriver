import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HIDDescriptorContractTests {
  @Test(arguments: [GamepadHIDDescriptor.descriptor, XboxOneBluetoothHIDDescriptor.oneSDescriptor])
  func repositoryControllerDescriptorsSatisfyTheContract(descriptor: [UInt8]) {
    #expect(violation(Data(descriptor)) == nil)
  }

  @Test
  func minimalGamepadSatisfiesTheContract() {
    #expect(violation(application(stickXY + buttons)) == nil)
  }

  @Test
  func joystickAndMultiAxisCollectionsSatisfyTheContract() {
    for usage: UInt8 in [0x04, 0x08] {
      #expect(violation(application(stickXY + buttons, usage: usage)) == nil)
    }
  }

  @Test
  func hatSwitchIsADirectionalInput() {
    let hat: [UInt8] = [
      0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42, 0x75,
      0x04, 0x95, 0x01, 0x81, 0x01,
    ]
    #expect(violation(application(hat + buttons)) == nil)
  }

  @Test
  func missingDescriptorFailsClosed() {
    #expect(violation(nil) == .missingDescriptor)
    #expect(HIDDescriptorContract.violation(in: nil) == .missingDescriptor)
  }

  @Test
  func truncatedDescriptorFailsClosed() {
    let descriptor = Data(GamepadHIDDescriptor.descriptor.dropLast(1) + [0x26, 0xFF])
    #expect(violation(descriptor) == .malformedDescriptor)
  }

  @Test(
    arguments: [
      [0xFE, 0x00, 0x10],  // long item
      [0xA4],  // Push
      [0xB4],  // Pop
      [0x0C],  // reserved item type
      [0xC4],  // reserved global tag
      [0xB8],  // reserved local tag
      [0x69, 0x00],  // reserved local tag 0x6
      [0xA9, 0x01],  // Delimiter
      [0x00],  // reserved main tag
    ] as [[UInt8]]
  )
  func unmodeledItemsFailClosed(item: [UInt8]) {
    #expect(violation(application(item + stickXY + buttons)) == .unsupportedItem)
  }

  @Test
  func legalItemsTheParserIgnoresDoNotFail() {
    // Physical Minimum/Maximum, Unit Exponent, Unit, and String Index.
    let ignored: [UInt8] = [0x35, 0x00, 0x45, 0x01, 0x55, 0x00, 0x65, 0x00, 0x79, 0x01]
    #expect(violation(application(ignored + stickXY + buttons)) == nil)
  }

  @Test
  func mixedNumberedAndUnnumberedInputReportsFail() {
    let numberedButtons: [UInt8] = [0x85, 0x01] + buttons
    #expect(violation(application(stickXY + numberedButtons)) == .mixedReportNumbering)
  }

  @Test
  func zeroSizedOrOversizedFieldsFail() {
    let zeroCount: [UInt8] = [0x75, 0x08, 0x95, 0x00, 0x81, 0x02]
    let zeroSize: [UInt8] = [0x75, 0x00, 0x95, 0x01, 0x81, 0x01]
    let oversized: [UInt8] = [0x09, 0x32, 0x75, 0x21, 0x95, 0x01, 0x81, 0x02]
    for field in [zeroCount, zeroSize, oversized] {
      #expect(violation(application(stickXY + field + buttons)) == .invalidFieldSize)
    }
  }

  @Test
  func controlsBeyondTheUsageListAreUnusedPadding() {
    // HID 1.11 section 6.2.2.8 repeats the last usage for the remaining controls:
    // buttons 13-16 repeat Button 12 and the last two bytes repeat Y.
    let paddedButtons: [UInt8] = [
      0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02,
      0x09, 0x30, 0x09, 0x31, 0x81, 0x02, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0C, 0x15, 0x00, 0x25,
      0x01, 0x75, 0x01, 0x95, 0x10, 0x81, 0x02, 0xC0,
    ]
    #expect(violation(Data(paddedButtons)) == nil)
    let paddedAxes: [UInt8] = [
      0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02,
    ]
    #expect(violation(application(paddedAxes + buttons)) == nil)
    let parsed = HIDReportDescriptorParser.parse(descriptor: paddedButtons)
    #expect(parsed?.fields.filter { $0.usagePage == 0x09 }.map(\.usage) == Array(1...12))
  }

  @Test
  func arrayInputIsASelectorOverItsUsageRange() throws {
    // Six selectors over Buttons 1-4.
    let buttonArray: [UInt8] = [
      0x05, 0x09, 0x19, 0x01, 0x29, 0x04, 0x15, 0x01, 0x25, 0x04, 0x75, 0x08, 0x95, 0x06, 0x81,
      0x00,
    ]
    let descriptor = application(stickXY + buttonArray)
    #expect(violation(descriptor) == nil)
    let parsed = try #require(HIDReportDescriptorParser.parse(descriptor: Array(descriptor)))
    #expect(!parsed.fields.contains { $0.usagePage == 0x09 })
    #expect(parsed.arrays.count == 1)
    #expect(parsed.arrays.first?.count == 6)
    #expect(parsed.arrays.first?.usages.map(\.usage) == [1, 2, 3, 4])
  }

  @Test
  func extendedUsageCarriesItsOwnPage() {
    // Generic Desktop X and Y as 4-byte usages under a vendor Usage Page.
    let extendedXY: [UInt8] = [
      0x06, 0x00, 0xFF, 0x0B, 0x30, 0x00, 0x01, 0x00, 0x0B, 0x31, 0x00, 0x01, 0x00, 0x15, 0x00,
      0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02,
    ]
    #expect(violation(application(extendedXY + buttons)) == nil)
  }

  @Test
  func unbalancedCollectionsAreMalformed() {
    #expect(violation(application(stickXY + buttons) + Data([0xC0])) == .malformedDescriptor)
    let unclosed = Data([0x05, 0x01, 0x09, 0x05, 0xA1, 0x01] + stickXY + buttons)
    #expect(violation(unclosed) == .malformedDescriptor)
  }

  @Test
  func repeatedStandardUsageInOneReportFails() {
    let repeatedX: [UInt8] = [0x09, 0x30, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02]
    let explicitPair: [UInt8] = [0x09, 0x30, 0x09, 0x30, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02]
    let repeatedButton: [UInt8] = [
      0x05, 0x09, 0x09, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0x75, 0x07, 0x95, 0x01, 0x81,
      0x01,
    ]
    #expect(violation(application(stickXY + repeatedX + buttons)) == .duplicateUsage)
    #expect(violation(application(stickXY + buttons + repeatedButton)) == .duplicateUsage)
    #expect(violation(application(stickXY + explicitPair + buttons)) == .duplicateUsage)
  }

  @Test
  func theSameUsageInDifferentReportsPasses() {
    let first: [UInt8] = [0x85, 0x01] + stickXY + buttons
    let second: [UInt8] = [0x85, 0x02] + stickXY + buttons
    #expect(violation(application(first + second)) == nil)
  }

  @Test
  func nonControllerApplicationCollectionFails() {
    // Generic Desktop Mouse.
    #expect(violation(application(stickXY + buttons, usage: 0x02)) == .missingControllerCollection)
  }

  @Test
  func missingDirectionalInputFails() {
    let zAxis: [UInt8] = [0x05, 0x01, 0x09, 0x32, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02]
    #expect(violation(application(zAxis + buttons)) == .missingDirectionalInput)
  }

  @Test
  func singleStickAxisIsNotADirectionalInput() {
    let xOnly: [UInt8] = [0x05, 0x01, 0x09, 0x30, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02]
    #expect(violation(application(xOnly + buttons)) == .missingDirectionalInput)
  }

  @Test
  func missingButtonInputFails() { #expect(violation(application(stickXY)) == .missingButtonInput) }

  @Test
  func directionalAndButtonsMustShareAControllerCollection() {
    // A mouse with relative X/Y and buttons beside a joystick with only vendor input.
    let relativeXY: [UInt8] = [
      0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06,
    ]
    let mouse = [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01] + relativeXY + buttons + [0xC0]
    let vendorJoystick: [UInt8] = [
      0x05, 0x01, 0x09, 0x04, 0xA1, 0x01, 0x06, 0x00, 0xFF, 0x09, 0x01, 0x75, 0x08, 0x95, 0x08,
      0x81, 0x02, 0xC0,
    ]
    #expect(violation(Data(mouse + vendorJoystick)) == .missingDirectionalInput)
    // Stick in one controller collection, buttons in another.
    let stickOnly = [0x05, 0x01, 0x09, 0x05, 0xA1, 0x01] + stickXY + [0xC0]
    let buttonsOnly = [0x05, 0x01, 0x09, 0x05, 0xA1, 0x01] + buttons + [0xC0]
    #expect(violation(Data(stickOnly + buttonsOnly)) == .missingButtonInput)
  }

  @Test
  func relativeAxesAreNotADirectionalInput() {
    let relativeXY: [UInt8] = [
      0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06,
    ]
    #expect(violation(application(relativeXY + buttons)) == .missingDirectionalInput)
  }

  @Test
  func buttonUsageZeroIsNotAButton() {
    let noUsage: [UInt8] = [0x05, 0x09, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02]
    let usageZero: [UInt8] = [0x05, 0x09, 0x09, 0x00, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02]
    #expect(violation(application(stickXY + noUsage)) == .missingButtonInput)
    #expect(violation(application(stickXY + usageZero)) == .missingButtonInput)
  }

  @Test
  func inputReportLengthMatchesTheHostCount() {
    // The Xbox One S Bluetooth report 0x01 carries 15 payload bytes (four 16-bit sticks, two
    // 16-bit triggers, the hat byte, two button bytes) plus its report ID.
    let xbox = Data(XboxOneBluetoothHIDDescriptor.oneSDescriptor)
    #expect(violation(xbox, maximumInputLength: 16) == nil)
    #expect(violation(xbox, maximumInputLength: 15) == .reportLengthMismatch)
    #expect(violation(xbox, maximumInputLength: 17) == .reportLengthMismatch)
    // Unnumbered reports have no ID byte: stick (2) and buttons (1).
    #expect(violation(application(stickXY + buttons), maximumInputLength: 3) == nil)
    #expect(
      violation(application(stickXY + buttons), maximumInputLength: 4) == .reportLengthMismatch
    )
  }

  @Test
  func vendorOnlyControlsFail() {
    let vendor: [UInt8] = [
      0x06, 0x00, 0xFF, 0x09, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x3F, 0x81,
      0x02,
    ]
    #expect(violation(application(vendor)) == .missingDirectionalInput)
  }

  @Test
  func constantPaddingDoesNotCountAsInput() {
    let padding: [UInt8] = [0x75, 0x08, 0x95, 0x02, 0x81, 0x01]
    #expect(violation(application(padding + buttons)) == .missingDirectionalInput)
  }

  /// Generic Desktop X and Y, 8 bits each.
  private let stickXY: [UInt8] = [
    0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81,
    0x02,
  ]

  /// Buttons 1-8, one bit each.
  private let buttons: [UInt8] = [
    0x05, 0x09, 0x19, 0x01, 0x29, 0x08, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
  ]

  private func violation(
    _ descriptor: Data?,
    maximumInputLength: UInt32? = nil
  ) -> HIDDescriptorContract.Violation? {
    HIDDescriptorContract.violation(
      in: HIDLayoutSummary(
        reportDescriptor: descriptor,
        reports: [PhysicalHIDReportSignature(kind: .input, maximumLengthBytes: maximumInputLength)]
      )
    )
  }

  private func application(_ body: [UInt8], usage: UInt8 = 0x05) -> Data {
    Data([0x05, 0x01, 0x09, usage, 0xA1, 0x01] + body + [0xC0])
  }
}
