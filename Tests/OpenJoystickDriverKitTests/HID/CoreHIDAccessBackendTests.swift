import CoreHID
import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CoreHIDAccessBackendTests {
  @available(macOS 15, *)
  @Test
  func ds4SubscribesOnlyToRawReportsAndForwardsOnlyReports() {
    let plan = CoreHIDInputSubscriptionPlan.resolve(
      for: DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    )

    #expect(plan.monitorsRawReports)
    #expect(!plan.subscribesToElement(usagePage: 0x01, usage: 0x30))
    #expect(!plan.subscribesToElement(usagePage: 0xFF00, usage: 1))
    #expect(plan.forwards(.rawReport))
    #expect(!plan.forwards(.elementUpdates))
  }

  @available(macOS 15, *)
  @Test
  func knownAndUnknownGenericHIDDevicesUseOnlySupportedElements() {
    let identifiers = [
      DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600),
      DeviceIdentifier(vendorID: 0xFFFE, productID: 1),
    ]

    for identifier in identifiers {
      let plan = CoreHIDInputSubscriptionPlan.resolve(for: identifier)
      #expect(!plan.monitorsRawReports)
      #expect(plan.subscribesToElement(usagePage: 0x01, usage: 0x30))
      #expect(plan.subscribesToElement(usagePage: 0x09, usage: 1))
      #expect(!plan.subscribesToElement(usagePage: 0x01, usage: 0x36))
      #expect(!plan.subscribesToElement(usagePage: 0x0C, usage: 1))
      #expect(!plan.forwards(.rawReport))
      #expect(plan.forwards(.elementUpdates))
    }
  }

  @available(macOS 15, *)
  @Test
  func reportIdentifiersAreReconstructedOnlyWhenMissing() {
    let reportID = HIDReportID(rawValue: 1)
    #expect(
      CoreHIDInputReport.normalizedBytes(reportID: reportID, data: Data([2, 3])) == [1, 2, 3]
    )
    #expect(
      CoreHIDInputReport.normalizedBytes(reportID: reportID, data: Data([1, 2, 3])) == [1, 2, 3]
    )
    #expect(CoreHIDInputReport.normalizedBytes(reportID: nil, data: Data([2, 3])) == [2, 3])
  }

  @available(macOS 15, *)
  @Test
  func coreHIDElementReportIdentifiersArePreserved() {
    #expect(CoreHIDElementReportID.value(HIDReportID(rawValue: 6)) == 6)
    #expect(CoreHIDElementReportID.value(nil) == nil)
  }

  @Test
  func legacyHIDElementReportIdentifiersArePreservedWithoutNarrowing() {
    #expect(IOHIDElementReportID.value(6) == 6)
    #expect(IOHIDElementReportID.value(UInt32.max) == UInt32.max)
  }

  @available(macOS 15, *)
  @Test
  func physicalSetReportUsesFiniteTimeoutAndCompletesFailures() async throws {
    struct ExpectedFailure: Error {}
    var receivedTimeout: Duration?

    let result = await CoreHIDPhysicalReportRequest.perform { timeout in
      receivedTimeout = timeout
      throw ExpectedFailure()
    }

    #expect(receivedTimeout == .seconds(2))
    if case .success = result { Issue.record("A failed set-report request unexpectedly succeeded") }
  }

  // Fanatec ClubSport Wheel Base V2.5 (0EB7:0004): X/Z/Rz are 16-bit, logical 0...65535.
  // CoreHID reported the wheel centre (0x8000) as -32768; captured on hardware.
  @Test
  func unsignedSixteenBitElementValuesAreNotSignExtended() {
    let cases: [(raw: Int, expected: Int)] = [
      (0, 0), (32_767, 32_767), (-32_768, 32_768), (-26_597, 38_939), (-1, 65_535),
    ]
    for (raw, expected) in cases {
      #expect(
        CoreHIDElementInteger.value(signExtended: raw, reportSize: 16, logicalMinimum: 0)
          == expected
      )
    }
  }

  @Test
  func signedAndUnsignedEightBitElementValuesKeepTheirMeaning() {
    #expect(
      CoreHIDElementInteger.value(signExtended: -128, reportSize: 8, logicalMinimum: -128) == -128
    )
    #expect(
      CoreHIDElementInteger.value(signExtended: -1, reportSize: 8, logicalMinimum: -127) == -1
    )
    #expect(CoreHIDElementInteger.value(signExtended: -1, reportSize: 8, logicalMinimum: 0) == 255)
    #expect(CoreHIDElementInteger.value(signExtended: 200, reportSize: 8, logicalMinimum: 0) == 200)
  }

  @Test
  func unsignedWheelCentreNormalizesToCentreInGenericHIDParser() {
    let parser = GenericHIDParser(identifier: DeviceIdentifier(vendorID: 0x0EB7, productID: 0x0004))
    func x(_ raw: Int) -> [ControllerEvent] {
      parser.parse(
        elementValue: HIDElementValue(
          usagePage: 0x01,
          usage: 0x30,
          logicalMinimum: 0,
          logicalMaximum: 65_535,
          integerValue: CoreHIDElementInteger.value(
            signExtended: Int(Int16(truncatingIfNeeded: raw)),
            reportSize: 16,
            logicalMinimum: 0
          )
        )
      )
    }
    guard case .leftStickChanged(let centre, _)? = x(0x8000).first,
      case .leftStickChanged(let right, _)? = x(0xFFFF).first,
      case .leftStickChanged(let left, _)? = x(0).first
    else {
      Issue.record("expected left stick events")
      return
    }
    #expect(abs(centre) < 0.001)
    #expect(right == 1)
    #expect(left == -1)
  }
}
