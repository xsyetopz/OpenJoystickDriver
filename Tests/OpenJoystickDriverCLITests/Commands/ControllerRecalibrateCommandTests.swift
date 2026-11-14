import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ControllerRecalibrateCommandTests {
  private static func service(
    answering result: ControllerRecalibrationResult
  ) throws -> FakeService {
    let reply = try JSONEncoder().encode(result)
    return try FakeService(devices: [ApplicationServiceDeviceDescription.fixture(id: "pad-1")]) {
      method,
      _ in method == .recalibrateController ? reply : nil
    }
  }

  private func sent(by service: FakeService) throws -> [ControllerRecalibrationArguments] {
    try service.arguments(of: .recalibrateController).map {
      try JSONDecoder().decode(ControllerRecalibrationArguments.self, from: $0)
    }
  }

  @Test
  func sticksStepReportsStoredValuesAndNamesTheControlThatDidNotMove() async throws {
    let service = try Self.service(
      answering: ControllerRecalibrationResult(
        action: .triggers,
        stored: ControllerCalibration(values: [.leftTriggerFull: 0.9]),
        unmoved: [.rightTrigger]
      )
    )

    let result = await service.run([
      "controller", "calibrate", token("pad-1"), "sticks", "--step", "triggers", "--json",
    ])

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["kind"] as? String == "Recalibration")
    #expect(json["action"] as? String == "triggers")
    #expect((json["stored"] as? [String: Double])?["leftTriggerFull"] == 0.9)
    #expect(json["unmoved"] as? [String] == ["RightTrigger"])
    let arguments = try #require(try sent(by: service).first)
    #expect(arguments.action == .triggers)
    #expect(arguments.controller == .session(.fixture("pad-1")))
  }

  @Test
  func resetSendsTheResetActionAndReportsTheClearedKeys() async throws {
    let service = try Self.service(
      answering: ControllerRecalibrationResult(
        action: .reset,
        cleared: [.leftStickCenterX],
        gyroOffsetCleared: true
      )
    )

    let result = await service.run(["controller", "calibrate", token("pad-1"), "reset", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["cleared"] as? [String] == ["leftStickCenterX"])
    #expect(json["gyroOffsetCleared"] as? Bool == true)
    #expect(try sent(by: service).map(\.action) == [.reset])
  }

  @Test
  func refusedRecalibrationFailsWithTheServiceReason() async throws {
    let service = try Self.service(
      answering: ControllerRecalibrationResult(action: .reset, failure: .noRecord)
    )

    let result = await service.run(["controller", "calibrate", token("pad-1"), "reset", "--json"])

    #expect(result.code != 0)
  }
}
