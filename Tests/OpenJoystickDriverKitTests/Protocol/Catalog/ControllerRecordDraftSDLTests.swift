import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The record `ojd record draft --from-sdl` builds from a database line and a pad's elements.
struct ControllerRecordDraftSDLTests {
  /// A model without a bundled record, as the fixture's pad is.
  private static let backbone = ControllerModelID(vendorID: 0x358A, productID: 0x0201)

  private func fixture() throws -> SDLMappingFixture {
    try #require(SDLMappingFixture.all()["backbone-one"])
  }

  private func draft(
    _ fixture: SDLMappingFixture,
    model: ControllerModelID = backbone,
    line: String? = nil,
    device: PhysicalDevice? = nil
  ) throws -> ControllerRecordDraft {
    try ControllerRecordDraft(
      model: model,
      device: device ?? fixture.physicalDevice,
      database: SDLGameControllerDatabase(text: line ?? fixture.line)
    )
  }

  private func failure(_ attempt: () throws -> Void) -> ControllerRecordDraft.SDLFailure? {
    do {
      try attempt()
    } catch {
      return error as? ControllerRecordDraft.SDLFailure
    }
    return nil
  }

  @Test
  func draftsControllerRecordWhoseMapIsConvertedLine() throws {
    let fixture = try fixture()
    let draft = try draft(fixture)
    #expect(draft.operation == .add && draft.family == .hidDescriptor)
    #expect(draft.reportID == nil && draft.reportLength == nil && draft.changedBytes.isEmpty)

    let validated = try ControllerRecordSet.validate(draft.document)
    let map = try #require(validated.record?.profile.hidUsageMap)
    #expect(map.rendered.sorted() == fixture.expected.sorted())
  }

  @Test
  func recordWritesEveryBindingKindFixturesGive() throws {
    for (name, fixture) in try SDLMappingFixture.all() {
      let draft = try draft(fixture, model: ControllerModelID(vendorID: 0x1234, productID: 0x5678))
      let validated = try ControllerRecordSet.validate(draft.document)
      let map = try #require(validated.record?.profile.hidUsageMap, "\(name)")
      #expect(map.rendered.sorted() == fixture.expected.sorted(), "\(name)")
    }
  }

  @Test
  func modelWithBundledRecordIsRefused() throws {
    let fixture = try fixture()
    let bundled = ControllerModelID(vendorID: 0x2DC8, productID: 0x301C)
    #expect(failure { _ = try draft(fixture, model: bundled) } == .hasRecord)
  }

  @Test
  func padWithoutDescriptorIsRefusedWithRule() throws {
    let fixture = try fixture()
    let device = PhysicalDevice(
      vendorID: fixture.device.vendorID,
      productID: fixture.device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(elements: fixture.elements)
        )
      ]
    )
    #expect(
      failure { _ = try draft(fixture, device: device) } == .descriptorContract(.missingDescriptor)
    )
  }

  @Test
  func padWithNoLineNamesGUIDItWasSearchedWith() throws {
    let fixture = try fixture()
    let other = "03000000c82d00005106000000010000,Other,a:b0,platform:Mac OS X,"
    #expect(
      failure { _ = try draft(fixture, line: other) }
        == .noLine(guid: "0300a0ab8a3500000102000000010000")
    )
  }

  @Test
  func lineThatDoesNotConvertIsRejectedWithItsReason() throws {
    let fixture = try fixture()
    let line = fixture.line.replacingOccurrences(of: "a:b0,", with: "a:b99,")
    guard case .rejected(let reason)? = failure({ _ = try draft(fixture, line: line) }) else {
      Issue.record("expected a rejection")
      return
    }
    #expect(!reason.isEmpty)
  }
}
