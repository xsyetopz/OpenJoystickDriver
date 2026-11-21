import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension ControllerRecordWriterTests {
  private static let unitA = ControllerPortKey(rawValue: "U-AAAAAAAAAAAAAAAA")!
  private static let unitB = ControllerPortKey(rawValue: "U-BBBBBBBBBBBBBBBB")!

  @Test
  func unitCalibrationWritesItsOwnPatchAndOverlaysTheModel() throws {
    try Self.withDirectory { directory, _ in
      try Self.write(.set(.leftStickCenterX, 0.05), for: .model(Self.bundledHID), in: directory)
      let change = try Self.change(
        .set(.leftStickCenterX, 0.2),
        for: .unit(Self.bundledHID, Self.unitA),
        in: directory
      )
      #expect(change.created)
      #expect(change.previousTuning == 0.05)
      #expect(change.file.lastPathComponent == "2c22-2000-U-AAAAAAAAAAAAAAAA.patch.plist")
      try ControllerRecordWriter.write(change)

      let records = ControllerRecordSet.load(userDirectory: directory)
      #expect(records.unitCalibrations[Self.unitA]?.values == [.leftStickCenterX: 0.2])
      let model = records.records[Self.bundledHID]?.tuning.calibration
      #expect(model?.values[.leftStickCenterX] == 0.05)
      let catalog = DeviceCatalog(records: records)
      func centerX(_ unit: ControllerPortKey?) -> Double? {
        catalog.calibration(of: Self.bundledHID, unit: unit).values[.leftStickCenterX]
      }
      #expect(centerX(Self.unitA) == 0.2)
      #expect(centerX(Self.unitB) == 0.05)
      #expect(centerX(nil) == 0.05)
    }
  }

  @Test
  func unitTargetRefusesATuningKeyOutsideCalibration() throws {
    try Self.withDirectory { directory, _ in
      #expect(throws: ControllerRecordWriter.TuningFailure.self) {
        try Self.change(
          .set(.stickDeadzone, 0.1),
          for: .unit(Self.bundledHID, Self.unitA),
          in: directory
        )
      }
    }
  }

  @Test
  func removingTheLastUnitValueRemovesTheFile() throws {
    try Self.withDirectory { directory, _ in
      let target = ControllerRecordWriter.Target.unit(Self.bundledHID, Self.unitA)
      try Self.write(.set(.gyroOffsetX, 0.01), for: target, in: directory)
      let change = try Self.change(.remove(.gyroOffsetX), for: target, in: directory)
      #expect(change.previousTuning == 0.01)
      #expect(change.data == nil)
      try ControllerRecordWriter.write(change)
      #expect(ControllerRecordSet.load(userDirectory: directory).unitCalibrations.isEmpty)
    }
  }

  @Test
  func unitPatchOfAModelWithNoRecordIsRefused() throws {
    try Self.withDirectory { directory, _ in
      let unknown = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
      #expect(throws: ControllerRecordWriter.TuningFailure.refused(.noRecord(unknown))) {
        try Self.change(.set(.gyroOffsetX, 0.01), for: .unit(unknown, Self.unitA), in: directory)
      }
    }
  }
}
