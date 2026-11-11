import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The families whose descriptions hold the input layout, which `ReportLayoutDriver` decodes:
/// `XboxXID`, `NintendoSwitchInputOnly` and `VendorFlydigi`.
///
/// Their decoded frames are pinned by `DriverParseCharacterizationTests`, `XboxXIDFieldSweepTests`
/// and each family's parser suite.
struct DescribedLayoutFamilyTests {
  private static let described: [PhysicalProtocolID] = [
    .xboxXID, .nintendoSwitchInputOnly, .vendorFlydigi,
  ]

  @Test(arguments: described)
  func descriptionsDeclareTheirLayoutThroughTheInputSection(family: PhysicalProtocolID) {
    let description = family.protocolDescription
    #expect(description.recordSections.contains(.input))
    #expect(description.inputLayouts != nil)
    #expect(!family.requiresRecordInputLayout)
  }

  @Test(arguments: described)
  func advertisedControlsContainEveryControlTheLayoutDecodes(family: PhysicalProtocolID) throws {
    let layout = try #require(family.protocolDescription.inputLayouts)
    #expect(layout.controls.isSubset(of: family.describedControls.controls))
    let driver = ReportLayoutDriver(
      describedBy: family,
      variant: nil,
      rumbleTemplate: nil,
      outEndpoint: 0x02,
      tuning: nil
    )
    #expect(driver.capabilities == family.describedControls)
  }

  /// `ReportLayoutDriver(describedBy:)` traps on a description that sets no input layout, so
  /// the registry may route only the families that set one.
  @Test
  func exactlyTheDescribedFamiliesSetAnInputLayout() {
    let withLayout = PhysicalProtocolID.allCases.filter {
      $0.protocolDescription.inputLayouts != nil
    }
    #expect(Set(withLayout) == Set(Self.described))
  }

  /// `ReportLayoutDriver` traps when a raw-USB rumble template has no USB output, so every
  /// variant's raw-USB template must send through the output the described initializer supplies.
  @Test(arguments: described)
  func everyRawUSBRumbleTemplateSendsThroughTheDriversUSBOutput(
    family: PhysicalProtocolID
  ) throws {
    let variants: [PhysicalProtocolVariantID?] =
      family.variants.isEmpty ? [nil] : Array(family.variants)
    let running = RumbleIntensities(lowFrequency: UnipolarValue(0x8000))
    for variant in variants {
      guard case .usb? = family.rumbleTemplate(variant: variant, record: nil)?.target else {
        continue
      }
      let driver = ReportLayoutDriver(
        describedBy: family,
        variant: variant,
        rumbleTemplate: nil,
        outEndpoint: 0x02,
        tuning: nil
      )
      let writes = try driver.encode(.setRumble(running, duration: .held)).writes
      let sentOverUSB = writes.contains { write in
        if case .usb = write { true } else { false }
      }
      #expect(sentOverUSB, "\(family) \(String(describing: variant))")
    }
  }

  @Test
  func xidDeclaresTheTwentyByteReportOfAnyLength() throws {
    let layout = try #require(ProtocolDescription.bundled[.xboxXID]?.inputLayouts?.layouts.first)
    #expect(layout.reportID == nil)
    #expect(layout.minimumLength == 20)
    #expect(!layout.requiresExactLength)
  }

  @Test
  func switchInputOnlyDeclaresTheSevenByteReportWithoutAnID() throws {
    let layout = try #require(
      ProtocolDescription.bundled[.nintendoSwitchInputOnly]?.inputLayouts?.layouts.first
    )
    #expect(layout.reportID == nil)
    #expect(layout.minimumLength == 7)
    #expect(!layout.requiresExactLength)
  }

  @Test
  func flydigiDeclaresExactlyFifteenBytesWithReportID1() throws {
    let layout = try #require(
      ProtocolDescription.bundled[.vendorFlydigi]?.inputLayouts?.layouts.first
    )
    #expect(layout.reportID == 1)
    #expect(layout.minimumLength == 15)
    #expect(layout.requiresExactLength)
  }
}
