import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct ControllerRecalibrationRequestsTests {
  private static let model = ControllerModelID(vendorID: 0x2C22, productID: 0x2000)

  private static func withDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ControllerRecalibrationRequestsTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root.appendingPathComponent("Controllers", isDirectory: true))
  }

  private static func state(
    left: (Float, Float) = (0, 0),
    triggers: (Float, Float) = (0, 0)
  ) -> ControllerState {
    ControllerState(
      leftStick: StickPosition(
        x: BipolarValue(normalized: left.0),
        y: BipolarValue(normalized: left.1)
      ),
      leftTrigger: UnipolarValue(normalized: triggers.0),
      rightTrigger: UnipolarValue(normalized: triggers.1)
    )
  }

  private static func run(
    _ action: ControllerRecalibrationAction,
    samples: [ControllerState],
    stored: ControllerCalibration = .none,
    in directory: URL
  ) -> ControllerRecalibrationResult {
    ApplicationServiceServer.recalibrate(
      action,
      model: model,
      samples: samples,
      stored: stored,
      directory: directory
    )
  }

  private static func tuning(in directory: URL) -> ControllerTuning? {
    ControllerRecordSet.load(userDirectory: directory).records[model]?.tuning
  }

  @Test
  func restStepStoresTheOffCentreStickInTheUserRecord() throws {
    try Self.withDirectory { directory in
      let result = Self.run(
        .rest,
        samples: (0..<10).map { _ in Self.state(left: (0.2, 0)) },
        in: directory
      )
      #expect(result.failure == nil)
      #expect(abs((result.stored.values[.leftStickCenterX] ?? 9) - 0.2) < 0.001)
      let calibration = try #require(Self.tuning(in: directory)).calibration
      let shown = calibration.applying(to: Self.state(left: (0.2, 0)))
      #expect(abs(shown.leftStick.x.normalized) < 0.001)
    }
  }

  @Test
  func untouchedTriggerKeepsItsStoredValueAndIsNamed() throws {
    try Self.withDirectory { directory in
      let stored = ControllerCalibration(values: [.rightTriggerFull: 0.8])
      _ = Self.run(
        .triggers,
        samples: [Self.state(triggers: (0.9, 0))],
        stored: stored,
        in: directory
      )
      let result = Self.run(
        .triggers,
        samples: [Self.state(triggers: (0.9, 0))],
        stored: stored,
        in: directory
      )
      #expect(result.unmoved == [.rightTrigger])
      #expect(result.stored.values[.rightTriggerFull] == nil)
      let kept = try #require(Self.tuning(in: directory)).calibration
      #expect(kept.values[.leftTriggerFull] != nil)
      #expect(kept.values[.rightTriggerFull] == nil)
    }
  }

  @Test
  func resetRemovesEveryStoredKeyAndToleratesAnEmptyRecord() throws {
    try Self.withDirectory { directory in
      let empty = Self.run(.reset, samples: [], in: directory)
      #expect(empty.failure == nil)
      #expect(empty.cleared.isEmpty)
      _ = Self.run(.rest, samples: [Self.state(left: (0.2, 0.1))], in: directory)
      let reset = Self.run(.reset, samples: [], in: directory)
      #expect(reset.failure == nil)
      #expect(reset.cleared.contains(.leftStickCenterX))
      #expect(Self.tuning(in: directory)?.calibration.values.isEmpty ?? true)
    }
  }

  @Test
  func modelWithoutRecordIsRefused() throws {
    try Self.withDirectory { directory in
      let result = ApplicationServiceServer.recalibrate(
        .rest,
        model: ControllerModelID(vendorID: 0x1234, productID: 0xABCD),
        samples: [Self.state()],
        stored: .none,
        directory: directory
      )
      #expect(result.failure == .noRecord)
    }
  }

  @Test
  func stepWithNoSamplesNamesEveryControl() throws {
    try Self.withDirectory { directory in
      let result = Self.run(.circle, samples: [], in: directory)
      #expect(result.unmoved == ControllerCalibration.Step.circle.controls)
      #expect(result.stored == .none)
    }
  }

  @Test
  func gyroStepStoresTheOffsetInTheUserRecord() throws {
    try Self.withDirectory { directory in
      let result = ApplicationServiceServer.recalibrate(
        .gyro,
        model: Self.model,
        samples: [],
        gyro: [ControllerMotionVector(x: 0.02, y: 0, z: -0.04)],
        stored: .none,
        directory: directory
      )
      #expect(result.failure == nil)
      #expect(abs((result.stored.values[.gyroOffsetX] ?? 9) - 0.02) < 1e-9)
      let kept = try #require(Self.tuning(in: directory)).calibration
      #expect(abs((kept.values[.gyroOffsetZ] ?? 9) + 0.04) < 1e-9)
      let reset = Self.run(.reset, samples: [], in: directory)
      #expect(reset.cleared.contains(.gyroOffsetX))
      #expect(Self.tuning(in: directory)?.calibration.values.isEmpty ?? true)
    }
  }

  @Test
  func gyroStepOfAControllerWithNoGyroStoresNothing() throws {
    try Self.withDirectory { directory in
      let result = Self.run(.gyro, samples: [Self.state()], in: directory)
      #expect(result.failure == nil)
      #expect(result.stored == .none)
      #expect(result.unmoved.isEmpty)
    }
  }
}
