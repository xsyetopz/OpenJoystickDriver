@testable import OpenJoystickDriverKit

extension PhysicalProtocolID {
  /// `VendorFlydigi`, the documented family the app bundles.
  static let flydigi = Self(documented: "VendorFlydigi")
}

/// The drivers of the families whose descriptions hold the input layout, built the way the
/// registry builds them.
func xidDriver(
  outEndpoint: UInt8 = 0x02,
  rumbleTemplate: RumbleOutputTemplate? = nil,
  tuning: ControllerTuning? = nil
) -> ReportLayoutDriver {
  ReportLayoutDriver(
    describedBy: .xboxXID,
    variant: .gamepad,
    rumbleTemplate: rumbleTemplate,
    outEndpoint: outEndpoint,
    tuning: tuning
  )
}

func switchInputOnlyDriver() -> ReportLayoutDriver {
  ReportLayoutDriver(
    describedBy: .nintendoSwitchInputOnly,
    variant: nil,
    rumbleTemplate: nil,
    outEndpoint: 0x02,
    tuning: nil
  )
}

func flydigiDriver() -> ReportLayoutDriver {
  ReportLayoutDriver(
    describedBy: .flydigi,
    variant: nil,
    rumbleTemplate: nil,
    outEndpoint: 0x02,
    tuning: nil
  )
}
