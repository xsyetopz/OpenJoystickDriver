import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverPresentation

struct CalibrationDeadZoneTests {
  @Test
  func drawnDeadZoneIsTheValueControllerShowReports() throws {
    let tuning = ControllerTuning(stickDeadzone: 0.15)
    let report = try #require(ControllerShowReport.Tuning(tuning))
    let reported: Float = try #require(report.stickDeadzone)
    let rows = ControllerCalibrationRows.rows(
      input: .neutral,
      output: nil,
      deadZone: Double(reported)
    )
    let sticks = rows.filter { $0.control == .leftStick || $0.control == .rightStick }
    #expect(sticks.count == 2)
    for row in sticks {
      let drawn: Double = try #require(ControllerDeadZoneGauge.deadZoneEnd(of: row, width: 1))
      #expect(abs(drawn - Double(reported)) < 1e-6)
    }
  }

  @Test
  func triggerDrawsNoDeadZone() {
    let rows = ControllerCalibrationRows.rows(input: .neutral, output: nil, deadZone: 0.15)
    let triggers = rows.filter { $0.control == .leftTrigger || $0.control == .rightTrigger }
    let drawn = triggers.map { ControllerDeadZoneGauge.deadZoneEnd(of: $0, width: 100) }
    #expect(drawn == [nil, nil])
  }

  @Test
  func gaugeScalesTheDeadZoneToItsWidth() {
    let row = ControllerCalibrationRow(control: .leftStick, raw: 0.5, tuned: nil, deadZone: 0.2)
    #expect(ControllerDeadZoneGauge.deadZoneEnd(of: row, width: 50) == 10)
  }
}
