import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct ControllerTuningRequestsTests {
  /// A bundled `SonyDualShock4` record, a HID family.
  private static let bundledHID = (vendorID: 0x2C22, productID: 0x2000)

  /// Runs `body` with the `Controllers` folder of a temporary application-support folder, whose
  /// `Packages` store is empty.
  private static func withDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ControllerTuningRequestsTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root.appendingPathComponent("Controllers", isDirectory: true))
  }

  private static func set(
    _ value: Double?,
    model: (vendorID: Int, productID: Int) = bundledHID,
    in directory: URL
  ) -> ControllerTuningResult {
    ApplicationServiceServer.setControllerTuning(
      vendorID: model.vendorID,
      productID: model.productID,
      key: .stickDeadzone,
      value: value,
      directory: directory
    )
  }

  @Test
  func aValueIsWrittenAndRemoved() throws {
    try Self.withDirectory { directory in
      let written = Self.set(0.08, in: directory)
      #expect(written.failure == nil)
      #expect(written.created)
      #expect(written.previous == nil)
      #expect(written.file?.hasSuffix("Controllers/2c22-2000.patch.plist") == true)
      let model = ControllerModelID(vendorID: 0x2C22, productID: 0x2000)
      let loaded = ControllerRecordSet.load(userDirectory: directory)
      #expect(loaded.records[model]?.tuning.stickDeadzone == 0.08)

      let removed = Self.set(nil, in: directory)
      #expect(removed.failure == nil)
      #expect(removed.previous == 0.08)
      let file = try #require(removed.file)
      #expect(!FileManager.default.fileExists(atPath: file))
    }
  }

  @Test(arguments: [0.0, 1.0, -0.1, 1.5])
  func aValueOutOfRangeIsRefusedAndNothingIsWritten(_ value: Double) throws {
    try Self.withDirectory { directory in
      let result = Self.set(value, in: directory)
      #expect(result.failure == .invalidRecord)
      #expect(result.detail?.contains("stickDeadzone") == true)
      #expect(result.file == nil)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func removingAKeyThatIsNotSetIsRefused() throws {
    try Self.withDirectory { directory in
      #expect(Self.set(nil, in: directory).failure == .notSet)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func modelWithoutARecordIsRefused() throws {
    try Self.withDirectory { directory in
      let result = Self.set(0.1, model: (0x1234, 0xABCD), in: directory)
      #expect(result.failure == .noRecord)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test(arguments: [(-1, 0x2000), (0x2C22, 0x10000), (0x10000, 0x2000)])
  func aVendorOrProductIDOutOfRangeIsAnInvalidRequest(_ model: (Int, Int)) throws {
    try Self.withDirectory { directory in
      let result = Self.set(0.1, model: model, in: directory)
      #expect(result.failure == .invalidRequest)
      #expect(result.file == nil)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func resultRoundTripsThroughJSON() throws {
    let result = ControllerTuningResult(
      key: .stickDeadzone,
      value: 0.08,
      previous: nil,
      file: "/tmp/2c22-2000.patch.plist",
      created: true,
      failure: nil
    )
    let data = try JSONEncoder().encode(result)
    #expect(try JSONDecoder().decode(ControllerTuningResult.self, from: data) == result)
    let arguments = try JSONEncoder().encode(
      LocalServiceRPCControllerTuningArguments(
        vendorID: 1,
        productID: 2,
        key: .stickDeadzone,
        value: nil
      )
    )
    let object = try JSONSerialization.jsonObject(with: arguments) as? [String: Any]
    #expect(object?["key"] as? String == "stickDeadzone")
  }
}
