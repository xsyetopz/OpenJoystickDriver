import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct StickDeadzoneEditorTests {
  private static func device() -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x2C22,
      productID: 0x2000,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .exclusiveHID,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("deadzone-editor")
    )
  }

  @Test
  func lastChangeMadeWhileOneInFlightWrittenAfterIt() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let editor = StickDeadzoneEditor()
    let device = Self.device()
    var reads = 0

    let changes = [0.02, 0.03, 0.04].map { value in
      Task { await editor.change(to: value, for: device, viewModel: viewModel) { reads += 1 } }
    }
    for change in changes { await change.value }

    let requests = await gateway.tuningRequests
    #expect(requests.map(\.value) == [0.02, 0.04])
    #expect(reads == 2)
    #expect(!editor.isWriting)
  }

  @Test
  func resetMadeWhileOneInFlightWrittenAfterIt() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let editor = StickDeadzoneEditor()
    let device = Self.device()

    async let first: Void = editor.change(to: 0.02, for: device, viewModel: viewModel) {}
    async let second: Void = editor.change(to: nil, for: device, viewModel: viewModel) {}
    _ = await (first, second)

    let requests = await gateway.tuningRequests
    #expect(requests.map(\.value) == [0.02, nil])
    #expect(!editor.isWriting)
  }

  @Test
  func theEditorStaysBusyUntilTheRecordIsRead() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let editor = StickDeadzoneEditor()
    var busyWhileReading: Bool?

    await editor.change(to: 0.02, for: Self.device(), viewModel: viewModel) {
      busyWhileReading = editor.isWriting
    }

    #expect(busyWhileReading == true)
    #expect(!editor.isWriting)
  }

  @Test
  func aRefusedChangeDoesNotReadTheRecordAndFreesTheEditor() async {
    let gateway = GatewayStub()
    await gateway.setTuningFailure(.invalidRecord)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let editor = StickDeadzoneEditor()
    var reads = 0

    await editor.change(to: 1.5, for: Self.device(), viewModel: viewModel) { reads += 1 }

    #expect(reads == 0)
    #expect(!editor.isWriting)
  }
}
