import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Where a virtual device's frame-queue capacity comes from: the record, else its family's
/// description, else the schema default.
struct FrameQueueCapacityTests {
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // UserSpaceOutputDispatcher
    .deletingLastPathComponent()  // Backends
    .deletingLastPathComponent()  // Output
    .deletingLastPathComponent()  // OpenJoystickDriverKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()

  /// A bundled GIP record that sets no frame-queue capacity of its own.
  private func bareRecord() throws -> (model: ControllerModelID, record: DeviceRuntimeProfile) {
    let catalog = DeviceCatalog()
    for model in ControllerRecordSet.bundled.records.keys.sorted() {
      guard let record = catalog.record(for: model) else { continue }
      if record.physicalProtocolID == .xboxGIP, record.tuning.frameQueueCapacity == nil {
        return (model, record)
      }
    }
    Issue.record("the bundled catalog has no GIP record without a frame-queue capacity")
    throw CancellationError()
  }

  @Test
  func tuningDefaultAndRangeAreSchemas() throws {
    let url = Self.repository.appendingPathComponent("Resources/Schemas/controller.schema.json")
    let schema = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    let definitions = try #require(schema["$defs"] as? [String: Any])
    let tuning = try #require(definitions["tuning"] as? [String: Any])
    let properties = try #require(tuning["properties"] as? [String: Any])
    let property = try #require(properties["frameQueueCapacity"] as? [String: Any])

    #expect(property["default"] as? Int == ControllerTuning.defaultFrameQueueCapacity)
    #expect(property["minimum"] as? Int == ControllerTuning.frameQueueCapacityRange.lowerBound)
    #expect(property["maximum"] as? Int == ControllerTuning.frameQueueCapacityRange.upperBound)
  }

  @Test
  func noBundledDescriptionRepeatsDefault() {
    for (family, description) in ProtocolDescription.bundled {
      #expect(description.tuning?.frameQueueCapacity == nil, "\(family)")
    }
  }

  @Test
  func controllerWithNoRecordGetsDefault() {
    #expect(
      VirtualGamepadReportMapping.frameQueueCapacity(of: nil)
        == ControllerTuning.defaultFrameQueueCapacity
    )
  }

  @Test
  func recordWhoseFamilySetsNoValueGetsDefault() throws {
    #expect(
      VirtualGamepadReportMapping.frameQueueCapacity(of: try bareRecord().record)
        == ControllerTuning.defaultFrameQueueCapacity
    )
  }

  @Test
  func familyDescriptionValueBeatsDefault() throws {
    let record = try bareRecord().record
    let description = try ProtocolDescriptionFixture.decode(
      family: .xboxGIP,
      #""defaults": {"tuning": {"frameQueueCapacity": 8}}"#
    )

    #expect(
      VirtualGamepadReportMapping.frameQueueCapacity(
        of: record,
        descriptions: [.xboxGIP: description]
      ) == 8
    )
  }

  @Test
  func recordValueBeatsItsFamilyDescription() throws {
    let model = try bareRecord().model
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-frame-queue-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let json =
      #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"ControllerPatch","#
      + #""selector":{"vendorID":\#(model.vendorID),"productID":\#(model.productID)},"#
      + #""patch":{"tuning":{"frameQueueCapacity":4}}}"#
    try PropertyListFixture.bytes(json: json).write(
      to: directory.appendingPathComponent(ControllerPatch.Selector.identity(model).fileName)
    )
    let records = ControllerRecordSet.load(userDirectory: directory)
    let record = try #require(DeviceCatalog(records: records).record(for: model))
    let description = try ProtocolDescriptionFixture.decode(
      family: .xboxGIP,
      #""defaults": {"tuning": {"frameQueueCapacity": 8}}"#
    )

    #expect(
      VirtualGamepadReportMapping.frameQueueCapacity(
        of: record,
        descriptions: [.xboxGIP: description]
      ) == 4
    )
  }

  @Test(arguments: [0, 1_025])
  func descriptionCapacityOutsideRangeIsRefused(capacity: Int) {
    #expect(throws: ProtocolDescriptionProblem.self) {
      try ProtocolDescriptionFixture.decode(
        family: .xboxGIP,
        #""defaults": {"tuning": {"frameQueueCapacity": \#(capacity)}}"#
      )
    }
  }
}
