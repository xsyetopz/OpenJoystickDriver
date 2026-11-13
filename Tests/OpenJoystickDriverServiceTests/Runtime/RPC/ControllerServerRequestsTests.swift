import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct ControllerServerRequestsTests {
  /// A bundled `SonyDualShock4` record, a HID family.
  private static let bundledHID = (vendorID: 0x2C22, productID: 0x2000)
  /// A bundled `XboxGIP` record, a raw-USB family.
  private static let bundledGIP = (vendorID: 0x366C, productID: 0x0005)

  /// Runs `body` with the `Controllers` folder of a temporary application-support folder, whose
  /// `Packages` store is empty.
  private static func withDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ControllerServerRequestsTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root.appendingPathComponent("Controllers", isDirectory: true))
  }

  private static func set(
    _ model: (vendorID: Int, productID: Int),
    to server: ControllerServer,
    native: Bool,
    in directory: URL
  ) -> ControllerServerResult {
    ApplicationServiceServer.setControllerServer(
      vendorID: model.vendorID,
      productID: model.productID,
      server: server,
      servableBySystem: native,
      directory: directory
    )
  }

  private static func loadedOwnership(in directory: URL) -> ControllerServer? {
    ControllerRecordSet.load(userDirectory: directory)
      .records[ControllerModelID(vendorID: 0x2C22, productID: 0x2000)]?.server
  }

  @Test
  func nativeModelIsWrittenAndSwitchedBack() throws {
    try Self.withDirectory { directory in
      let toOJD = Self.set(Self.bundledHID, to: .ojd, native: true, in: directory)
      #expect(toOJD.failure == nil)
      #expect(toOJD.previous == .system)
      #expect(toOJD.created)
      #expect(toOJD.file?.hasSuffix("Controllers/2c22-2000.patch.plist") == true)
      #expect(Self.loadedOwnership(in: directory) == .ojd)

      // A model OJD already serves counts as native, as its seized controller is no gamepad.
      let back = Self.set(Self.bundledHID, to: .system, native: false, in: directory)
      #expect(back.failure == nil)
      #expect(back.previous == .ojd)
      #expect(!back.created)
      #expect(Self.loadedOwnership(in: directory) == .system)
    }
  }

  @Test
  func modelBundledRecordGivesToOJDReleasedAndClaimedBack() throws {
    try Self.withDirectory { directory in
      let ultimate2C = (vendorID: 0x2DC8, productID: 0x301B)
      let released = Self.set(ultimate2C, to: .system, native: true, in: directory)
      #expect(released.failure == nil, "\(released.detail ?? "")")
      #expect(released.previous == .ojd)
      let claimed = Self.set(ultimate2C, to: .ojd, native: true, in: directory)
      #expect(claimed.failure == nil, "\(claimed.detail ?? "")")
      #expect(claimed.previous == .system)
      #expect(
        ControllerRecordSet.load(userDirectory: directory)
          .records[ControllerModelID(vendorID: 0x2DC8, productID: 0x301B)]?.server == .ojd
      )
    }
  }

  @Test
  func claimingUpstreamServerBackDropsPatchRemovesIt() throws {
    try Self.withDirectory { directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("2dc8-301b.patch.plist")
      let patch: [String: Any] = [
        "apiVersion": "openjoystickdriver/v1alpha3", "kind": "ControllerPatch",
        "selector": ["vendorID": 0x2DC8, "productID": 0x301B], "remove": ["server"],
      ]
      try PropertyListSerialization.data(fromPropertyList: patch, format: .xml, options: 0)
        .write(to: file)
      let claimed = Self.set((0x2DC8, 0x301B), to: .ojd, native: true, in: directory)
      #expect(claimed.failure == nil, "\(claimed.detail ?? "")")
      #expect(!FileManager.default.fileExists(atPath: file.path))
    }
  }

  @Test
  func rawUSBModelIsRefusedAndNothingIsWritten() throws {
    try Self.withDirectory { directory in
      let result = Self.set(Self.bundledGIP, to: .system, native: true, in: directory)
      #expect(result.failure == .rawUSB)
      #expect(result.file == nil)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func modelApplesDriverHoldsRefusedAndNothingWritten() throws {
    try Self.withDirectory { directory in
      let result = Self.set((0x045E, 0x02EA), to: .ojd, native: true, in: directory)
      #expect(result.failure == .rawUSB)
      #expect(result.file == nil)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func modelMacOSDoesNotServeIsRefused() throws {
    try Self.withDirectory { directory in
      let result = Self.set(Self.bundledHID, to: .ojd, native: false, in: directory)
      #expect(result.failure == .notNative)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func modelWithoutRecordIsRefused() throws {
    try Self.withDirectory { directory in
      let result = Self.set((0x1234, 0xABCD), to: .ojd, native: true, in: directory)
      #expect(result.failure == .noRecord)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test(arguments: [(-1, 0x2000), (0x2C22, 0x10000), (0x10000, 0x2000)])
  func vendorOrProductIDOutOfRangeIsInvalidRequest(_ model: (Int, Int)) throws {
    try Self.withDirectory { directory in
      let result = Self.set(model, to: .ojd, native: true, in: directory)
      #expect(result.failure == .invalidRequest)
      #expect(result.file == nil)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func invalidUserRecordIsRefusedAndKept() throws {
    try Self.withDirectory { directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("2c22-2000.patch.plist")
      let bytes = Data("{\"operation\": \"patch\"}".utf8)
      try bytes.write(to: file)
      let result = Self.set(Self.bundledHID, to: .ojd, native: true, in: directory)
      #expect(result.failure == .invalidRecord)
      #expect(result.detail != nil)
      #expect(try Data(contentsOf: file) == bytes)
    }
  }

  @Test
  func resultRoundTripsThroughJSON() throws {
    let result = ControllerServerResult(
      server: .ojd,
      previous: .system,
      file: "/tmp/2c22-2000.patch.plist",
      created: true,
      failure: nil
    )
    let data = try JSONEncoder().encode(result)
    #expect(try JSONDecoder().decode(ControllerServerResult.self, from: data) == result)
    let arguments = try JSONEncoder().encode(
      LocalServiceRPCControllerServerArguments(vendorID: 1, productID: 2, server: .system)
    )
    let object = try JSONSerialization.jsonObject(with: arguments) as? [String: Any]
    #expect(object?["server"] as? String == "System")
  }
}
