import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension ControllerRecordWriterTests {
  /// `stickDeadzone` is read by every family, so it applies to a HID record.
  @Test
  func tuningValueCreatesPatchOfOnlyThatKey() throws {
    try Self.withDirectory { directory, _ in
      let change = try Self.change(
        .set(.stickDeadzone, 0.08),
        for: .model(Self.bundledHID),
        in: directory
      )
      #expect(change.created)
      #expect(change.previousTuning == nil)
      #expect(change.file.lastPathComponent == "2c22-2000.patch.plist")
      try ControllerRecordWriter.write(change)
      let written = try Self.object(Data(contentsOf: change.file))
      #expect(written["kind"] as? String == "ControllerPatch")
      let patch = try #require(written["patch"] as? [String: [String: Double]])
      #expect(patch == ["tuning": ["stickDeadzone": 0.08]])
      let record = try #require(
        ControllerRecordSet.load(userDirectory: directory).records[Self.bundledHID]
      )
      #expect(record.tuning.stickDeadzone == 0.08)
      #expect(record.tuningLayers["stickDeadzone"] == .user)
    }
  }

  @Test
  func tuningValueKeepsServerAndNamesPreviousValue() throws {
    try Self.withDirectory { directory, _ in
      try ControllerRecordWriter.write(try Self.change(Self.bundledHID, to: .ojd, in: directory))
      try Self.write(.set(.stickDeadzone, 0.1), for: .model(Self.bundledHID), in: directory)
      let change = try Self.change(
        .set(.stickDeadzone, 0.2),
        for: .model(Self.bundledHID),
        in: directory
      )
      #expect(!change.created)
      #expect(change.previousTuning == 0.1)
      #expect(change.previousServer == .ojd)
      try ControllerRecordWriter.write(change)
      let fields = try Self.fields(change.file)
      #expect(fields["server"] as? String == "OJD")
      #expect(fields["tuning"] as? [String: Double] == ["stickDeadzone": 0.2])
    }
  }

  @Test
  func integerTuningValueIsWrittenAsInteger() throws {
    try Self.withDirectory { directory, _ in
      let change = try Self.change(
        .set(.frameQueueCapacity, 32),
        for: .allControllers,
        in: directory
      )
      let text = String(bytes: change.data ?? Data(), encoding: .utf8) ?? ""
      #expect(text.contains("<key>frameQueueCapacity</key>"))
      #expect(text.contains("<integer>32</integer>"))
    }
  }

  @Test
  func allControllersWritesAllPatch() throws {
    try Self.withDirectory { directory, _ in
      let change = try Self.change(
        .set(.stickDeadzone, 0.05),
        for: .allControllers,
        in: directory
      )
      #expect(change.created)
      #expect(change.file == ControllerDefaults.file(in: directory))
      try ControllerRecordWriter.write(change)
      let written = try Self.object(Data(contentsOf: change.file))
      #expect(written["selector"] as? [String: Bool] == ["all": true])
      #expect(
        ControllerRecordSet.load(userDirectory: directory).defaults?.tuning.stickDeadzone == 0.05
      )
      let next = try Self.change(
        .set(.stickDeadzone, 0.06),
        for: .allControllers,
        in: directory
      )
      #expect(next.previousTuning == 0.05)
    }
  }

  @Test(arguments: [0.0, 1.0, -0.1, 1.5])
  func outOfRangeDeadzoneWritesNothing(_ value: Double) throws {
    try Self.withDirectory { directory, _ in
      let targets: [ControllerRecordWriter.Target] = [.model(Self.bundledHID), .allControllers]
      for target in targets {
        do {
          _ = try Self.change(.set(.stickDeadzone, value), for: target, in: directory)
          Issue.record("\(value) was accepted")
        } catch {
          guard
            case .refused(.invalidResult(let problem)) = error
              as? ControllerRecordWriter.TuningFailure
          else {
            Issue.record("unexpected failure \(error)")
            return
          }
          #expect(problem.contains("stickDeadzone"))
        }
      }
      let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      #expect(files.isEmpty)
    }
  }

  @Test
  func fractionForIntegerKeyIsRefused() throws {
    try Self.withDirectory { directory, _ in
      #expect(throws: ControllerRecordWriter.TuningFailure.self) {
        try Self.change(.set(.frameQueueCapacity, 0.5), for: .allControllers, in: directory)
      }
    }
  }

  @Test
  func keyFamilyDoesNotReadIsRefusedForModel() throws {
    try Self.withDirectory { directory, _ in
      do {
        _ = try Self.change(
          .set(.lizardResendTicks, 10),
          for: .model(Self.bundledHID),
          in: directory
        )
        Issue.record("a key the family does not read was accepted")
      } catch {
        guard
          case .refused(.invalidResult(let problem)) = error
            as? ControllerRecordWriter.TuningFailure
        else {
          Issue.record("unexpected failure \(error)")
          return
        }
        #expect(problem.contains("lizardResendTicks"))
      }
    }
  }

  @Test
  func tuningForModelWithoutRecordIsRefused() throws {
    try Self.withDirectory { directory, _ in
      #expect(throws: ControllerRecordWriter.TuningFailure.refused(.noRecord(Self.unbundled))) {
        try Self.change(.set(.stickDeadzone, 0.1), for: .model(Self.unbundled), in: directory)
      }
    }
  }

  @Test
  func removingOneKeyKeepsOthers() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent("2c22-2000.patch.plist")
      try PropertyListFixture.data(
        tree: ControllerPatch.document(
          selector: .identity(Self.bundledHID),
          body: ["tuning": ["stickDeadzone": 0.1, "frameQueueCapacity": 32]]
        )
      )
      .write(to: file)
      let change = try Self.change(
        .remove(.stickDeadzone),
        for: .model(Self.bundledHID),
        in: directory
      )
      #expect(change.previousTuning == 0.1)
      try ControllerRecordWriter.write(change)
      #expect(try Self.fields(file)["tuning"] as? [String: Int] == ["frameQueueCapacity": 32])
    }
  }

  /// A record refuses an empty `tuning`, so the last key takes the section with it.
  @Test
  func removingLastKeyRemovesSection() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent("2c22-2000.patch.plist")
      try PropertyListFixture.data(
        tree: ControllerPatch.document(
          selector: .identity(Self.bundledHID),
          body: ["server": "OJD", "tuning": ["stickDeadzone": 0.1]]
        )
      )
      .write(to: file)
      try Self.write(.remove(.stickDeadzone), for: .model(Self.bundledHID), in: directory)
      #expect(try Self.fields(file).keys.sorted() == ["server"])
      #expect(ControllerRecordSet.load(userDirectory: directory).problems.isEmpty)
    }
  }

  @Test
  func removingLastKeyOfControllerFileRemovesSection() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent(
        ControllerRecordSet.fileName(for: Self.unbundled)
      )
      let record: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": 0x1234, "productID": 0xABCD,
        "modes": [["id": "default", "protocol": ["family": "HIDDescriptor"]]],
        "tuning": ["stickDeadzone": 0.1],
      ]
      try PropertyListFixture.data(tree: record).write(to: file)
      try Self.write(.remove(.stickDeadzone), for: .model(Self.unbundled), in: directory)
      #expect(try Self.object(Data(contentsOf: file))["tuning"] == nil)
      #expect(ControllerRecordSet.load(userDirectory: directory).problems.isEmpty)
    }
  }

  /// A patch needs a key, so removing its last one removes the file.
  @Test
  func removingLastKeyOfPatchRemovesFile() throws {
    try Self.withDirectory { directory, _ in
      try Self.write(.set(.stickDeadzone, 0.1), for: .allControllers, in: directory)
      let change = try Self.change(
        .remove(.stickDeadzone),
        for: .allControllers,
        in: directory
      )
      #expect(change.data == nil)
      try ControllerRecordWriter.write(change)
      #expect(!FileManager.default.fileExists(atPath: change.file.path))
      let loaded = ControllerRecordSet.load(userDirectory: directory)
      #expect(loaded.defaults?.tuning.stickDeadzone == nil)
    }
  }

  @Test
  func removingKeyThatIsNotSetIsRefused() throws {
    try Self.withDirectory { directory, _ in
      let notSet = ControllerRecordWriter.TuningFailure.notSet(.stickDeadzone)
      #expect(throws: notSet) {
        try Self.change(.remove(.stickDeadzone), for: .allControllers, in: directory)
      }
      #expect(throws: notSet) {
        try Self.change(.remove(.stickDeadzone), for: .model(Self.bundledHID), in: directory)
      }
      try ControllerRecordWriter.write(try Self.change(Self.bundledHID, to: .ojd, in: directory))
      #expect(throws: notSet) {
        try Self.change(.remove(.stickDeadzone), for: .model(Self.bundledHID), in: directory)
      }
    }
  }
}
